// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { OILimits } from "../../contracts/OILimits.sol";
import { IOILimits } from "../../contracts/interfaces/IOILimits.sol";
import { FixedPointMath } from "../../contracts/libraries/FixedPointMath.sol";

// ──────────────────────────────────────────────
// Minimal mocks for GhostOI tests
// ──────────────────────────────────────────────

contract MockMarketRegistry_GhostOI {
    struct MockMarket {
        uint256 tau;
        bool live;
        uint256 allocationWeight;
    }

    mapping(bytes32 => MockMarket) public markets;

    function setMarket(bytes32 id, uint256 tau, bool live_, uint256 weight) external {
        markets[id] = MockMarket(tau, live_, weight);
    }

    function getTau(bytes32 id) external view returns (uint256) { return markets[id].tau; }
    function isLive(bytes32 id) external view returns (bool) { return markets[id].live; }
    function getAllocationWeight(bytes32 id) external view returns (uint256) { return markets[id].allocationWeight; }
}

contract MockLeverVault_GhostOI {
    uint256 private _totalAssets;
    function setTotalAssets(uint256 val) external { _totalAssets = val; }
    function totalAssets() external view returns (uint256) { return _totalAssets; }
}

contract MockPositionManager_GhostOI {
    mapping(bytes32 => uint256[]) private _marketPositions;

    function getMarketPositions(bytes32 marketId) external view returns (uint256[] memory) {
        return _marketPositions[marketId];
    }

    function addPosition(bytes32 marketId, uint256 positionId) external {
        _marketPositions[marketId].push(positionId);
    }

    function clearPositions(bytes32 marketId) external {
        delete _marketPositions[marketId];
    }
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

/// @title GhostOITest
/// @notice Regression tests for LEVER-BUG-3: Ghost OI (stale open interest with zero positions).
///
/// Root cause: OI accumulators in OILimits persist across PositionManager redeployments.
/// When PositionManager state is wiped, OILimits still reports the old OI values,
/// blocking new position opens (cap appears consumed) and corrupting funding calculations.
///
/// Fix: adminResetMarketOIFull with on-chain position count verification and per-user OI clearing.
contract GhostOITest is Test {
    using FixedPointMath for uint256;

    uint256 constant WAD = 1e18;

    OILimits oiLimits;
    MockMarketRegistry_GhostOI registry;
    MockLeverVault_GhostOI vault;
    MockPositionManager_GhostOI posMgr;

    address admin   = address(0xAD);
    address engine  = address(0xE1);
    address alice   = address(0xA1);
    address bob     = address(0xA2);
    address charlie = address(0xA3);

    bytes32 marketId = keccak256("ELECTION_2028");

    function setUp() public {
        registry = new MockMarketRegistry_GhostOI();
        vault    = new MockLeverVault_GhostOI();
        posMgr   = new MockPositionManager_GhostOI();

        vm.prank(admin);
        oiLimits = new OILimits(address(registry), address(vault), address(posMgr), admin);

        vm.startPrank(admin);
        oiLimits.grantRole(oiLimits.EXECUTION_ENGINE_ROLE(), engine);
        vm.stopPrank();

        vault.setTotalAssets(10_000_000e18); // $10M TVL
        registry.setMarket(marketId, 48e18, false, 2e17); // 20% allocation
    }

    /// @dev Helper: simulate ghost OI by increasing OI (via engine role) then clearing PositionManager
    function _createGhostOI(address user, uint256 amount, bool isLong) internal {
        // Simulate position open via engine
        posMgr.addPosition(marketId, uint256(uint160(user))); // dummy position ID
        vm.prank(engine);
        oiLimits.increaseOI(marketId, user, isLong, amount);

        // Simulate PositionManager redeployment: wipe positions but OI persists
        posMgr.clearPositions(marketId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 1: adminResetMarketOIFull clears all OI accumulators including per-user
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice After reset, all five accumulators (global, market, long, short, per-user)
    ///         must be zero. The original adminResetMarketOI missed per-user OI.
    function test_adminReset_clearsAllOI() public {
        // Create ghost OI: alice=100K long, bob=80K short (within per-user cap of ~236K)
        _createGhostOI(alice, 100_000e18, true);
        _createGhostOI(bob, 80_000e18, false);

        // Verify ghost OI exists
        assertEq(oiLimits.getGlobalOI(), 180_000e18, "Ghost global OI should exist");
        assertEq(oiLimits.getMarketOI(marketId), 180_000e18, "Ghost market OI should exist");
        assertEq(oiLimits.getSideOI(marketId, true), 100_000e18, "Ghost long OI should exist");
        assertEq(oiLimits.getSideOI(marketId, false), 80_000e18, "Ghost short OI should exist");
        assertEq(oiLimits.getUserOI(marketId, alice), 100_000e18, "Ghost alice OI should exist");
        assertEq(oiLimits.getUserOI(marketId, bob), 80_000e18, "Ghost bob OI should exist");

        // PositionManager has zero positions (cleared by _createGhostOI)
        assertEq(posMgr.getMarketPositions(marketId).length, 0, "No open positions");

        // Admin resets with both users
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        vm.prank(admin);
        oiLimits.adminResetMarketOIFull(marketId, users);

        // ALL accumulators must be zero
        assertEq(oiLimits.getGlobalOI(), 0, "Global OI must be 0 after reset");
        assertEq(oiLimits.getMarketOI(marketId), 0, "Market OI must be 0 after reset");
        assertEq(oiLimits.getSideOI(marketId, true), 0, "Long OI must be 0 after reset");
        assertEq(oiLimits.getSideOI(marketId, false), 0, "Short OI must be 0 after reset");
        assertEq(oiLimits.getUserOI(marketId, alice), 0, "Alice per-user OI must be 0 after reset");
        assertEq(oiLimits.getUserOI(marketId, bob), 0, "Bob per-user OI must be 0 after reset");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 2: adminResetMarketOIFull reverts if positions still open
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Safety check: the function must revert if the market has any open positions.
    ///         Prevents misuse (clearing OI while live positions exist would break cap enforcement).
    function test_adminReset_revertsIfPositionsOpen() public {
        // Add a position WITHOUT clearing (simulating a live market)
        posMgr.addPosition(marketId, 1);
        vm.prank(engine);
        oiLimits.increaseOI(marketId, alice, true, 100_000e18);

        // Attempt reset while position exists
        address[] memory users = new address[](1);
        users[0] = alice;

        vm.expectRevert(
            abi.encodeWithSelector(IOILimits.OILimits__MarketHasOpenPositions.selector, marketId, 1)
        );
        vm.prank(admin);
        oiLimits.adminResetMarketOIFull(marketId, users);

        // OI must be unchanged
        assertEq(oiLimits.getMarketOI(marketId), 100_000e18, "OI unchanged after revert");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 3: adminResetMarketOIFull is a no-op on zero OI
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Calling reset on a market with no OI should not revert and should not change state.
    function test_adminReset_noopOnZeroOI() public {
        address[] memory users = new address[](0);

        // Should not revert
        vm.prank(admin);
        oiLimits.adminResetMarketOIFull(marketId, users);

        assertEq(oiLimits.getGlobalOI(), 0, "Global OI unchanged");
        assertEq(oiLimits.getMarketOI(marketId), 0, "Market OI unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Test 4: Partial user list clears listed users, leaves unlisted users unchanged
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Documents the limitation: if the admin provides an incomplete user list,
    ///         unlisted users retain their per-user OI cap consumption. Global/market/side
    ///         OI is still fully cleared.
    function test_adminReset_partialUserList() public {
        // Create ghost OI for three users
        _createGhostOI(alice, 200_000e18, true);
        _createGhostOI(bob, 150_000e18, false);
        _createGhostOI(charlie, 100_000e18, true);

        // Only provide alice and bob in the user list (omit charlie)
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        vm.prank(admin);
        oiLimits.adminResetMarketOIFull(marketId, users);

        // Global/market/side OI fully cleared
        assertEq(oiLimits.getGlobalOI(), 0, "Global OI cleared");
        assertEq(oiLimits.getMarketOI(marketId), 0, "Market OI cleared");
        assertEq(oiLimits.getSideOI(marketId, true), 0, "Long OI cleared");
        assertEq(oiLimits.getSideOI(marketId, false), 0, "Short OI cleared");

        // Listed users: per-user OI cleared
        assertEq(oiLimits.getUserOI(marketId, alice), 0, "Alice cleared");
        assertEq(oiLimits.getUserOI(marketId, bob), 0, "Bob cleared");

        // Unlisted user: per-user OI NOT cleared (known limitation)
        assertEq(oiLimits.getUserOI(marketId, charlie), 100_000e18,
            "Charlie NOT cleared (not in user list): known limitation");
    }
}
