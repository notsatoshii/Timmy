// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { MarketRegistry } from "../contracts/core/MarketRegistry.sol";
import { IMarketRegistry } from "../contracts/interfaces/IMarketRegistry.sol";

contract MarketRegistryTest is Test {
    MarketRegistry public registry;

    address public admin = address(0xA);
    address public keeper = address(0xB);
    address public manager = address(0xC);
    address public nobody = address(0xD);

    uint256 constant WAD = 1e18;
    uint256 constant SECONDS_PER_HOUR = 3600;

    bytes32 constant MARKET_ID = keccak256("TEST_MARKET");
    bytes32 constant MARKET_ID_2 = keccak256("TEST_MARKET_2");
    bytes32 constant MARKET_ID_3 = keccak256("TEST_MARKET_3");

    uint256 public resolutionTime;

    function setUp() public {
        vm.warp(1_000_000); // set a known start time
        resolutionTime = block.timestamp + 30 days;

        registry = new MarketRegistry(admin);

        // Grant roles
        vm.startPrank(admin);
        registry.grantRole(registry.KEEPER(), keeper);
        registry.grantRole(registry.MARKET_MANAGER(), manager);
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────

    function _createDefaultMarket() internal {
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Test Market",
            "polymarket-123",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
    }

    function _createAndActivate(bytes32 id) internal {
        vm.prank(manager);
        registry.createMarket(
            id,
            "Market",
            "ext-id",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
        vm.prank(keeper);
        registry.activateMarket(id);
    }

    // ─────────────────────────────────────────────────────
    // createMarket
    // ─────────────────────────────────────────────────────

    function test_createMarket_happyPath() public {
        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.MarketCreated(MARKET_ID, "Test Market", resolutionTime, 0);

        _createDefaultMarket();

        IMarketRegistry.Market memory m = registry.getMarket(MARKET_ID);
        assertEq(m.id, MARKET_ID);
        assertEq(m.name, "Test Market");
        assertEq(m.externalMarketId, "polymarket-123");
        assertEq(uint8(m.state), uint8(IMarketRegistry.MarketState.LISTED));
        assertEq(uint8(m.category), uint8(IMarketRegistry.MarketCategory.HIGH_LIQUIDITY));
        assertEq(m.resolutionTime, resolutionTime);
        assertEq(m.listingTime, block.timestamp);
        assertEq(m.allocationWeight, 0.5e18);
        assertFalse(m.isLive);
        assertEq(m.liveStartTime, 0);
        assertEq(m.outcome, 2);
        assertEq(m.externalResolutionTime, 0);
    }

    function test_createMarket_revert_duplicate() public {
        _createDefaultMarket();

        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketAlreadyExists.selector, MARKET_ID));
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Dup",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
    }

    function test_createMarket_revert_invalidResolutionTime_past() public {
        uint256 pastTime = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__InvalidResolutionTime.selector, pastTime));
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Past",
            "ext",
            pastTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
    }

    function test_createMarket_revert_invalidResolutionTime_now() public {
        uint256 nowTime = block.timestamp;
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__InvalidResolutionTime.selector, nowTime));
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Now",
            "ext",
            nowTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
    }

    function test_createMarket_revert_invalidWeight_zero() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__InvalidAllocationWeight.selector, 0));
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Zero",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0
        );
    }

    function test_createMarket_revert_invalidWeight_aboveWAD() public {
        uint256 overWAD = WAD + 1;
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__InvalidAllocationWeight.selector, overWAD));
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Over",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            overWAD
        );
    }

    function test_createMarket_weightExactlyWAD() public {
        vm.prank(manager);
        registry.createMarket(
            MARKET_ID,
            "Full",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            WAD
        );
        assertEq(registry.getAllocationWeight(MARKET_ID), WAD);
    }

    // ─────────────────────────────────────────────────────
    // activateMarket
    // ─────────────────────────────────────────────────────

    function test_activateMarket_happyPath() public {
        _createDefaultMarket();

        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.MarketLive(MARKET_ID, block.timestamp);

        vm.prank(keeper);
        registry.activateMarket(MARKET_ID);

        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.ACTIVE));
        assertEq(registry.activeMarketCount(), 1);

        bytes32[] memory active = registry.getActiveMarkets();
        assertEq(active.length, 1);
        assertEq(active[0], MARKET_ID);
    }

    function test_activateMarket_revert_notListed() public {
        _createAndActivate(MARKET_ID);

        // Already ACTIVE, try activating again
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketRegistry.MarketRegistry__InvalidStateTransition.selector,
                MARKET_ID,
                uint8(IMarketRegistry.MarketState.ACTIVE),
                uint8(IMarketRegistry.MarketState.ACTIVE)
            )
        );
        vm.prank(keeper);
        registry.activateMarket(MARKET_ID);
    }

    function test_activateMarket_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        vm.prank(keeper);
        registry.activateMarket(MARKET_ID);
    }

    // ─────────────────────────────────────────────────────
    // setLive
    // ─────────────────────────────────────────────────────

    function test_setLive_happyPath() public {
        _createAndActivate(MARKET_ID);

        uint256 liveTime = block.timestamp + 100;
        vm.warp(liveTime);

        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.MarketLive(MARKET_ID, liveTime);

        vm.prank(keeper);
        registry.setLive(MARKET_ID);

        assertTrue(registry.isLive(MARKET_ID));
        IMarketRegistry.Market memory m = registry.getMarket(MARKET_ID);
        assertEq(m.liveStartTime, liveTime);
    }

    function test_setLive_revert_notActive() public {
        _createDefaultMarket(); // LISTED state

        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotActive.selector, MARKET_ID));
        vm.prank(keeper);
        registry.setLive(MARKET_ID);
    }

    function test_isLive_defaultFalse() public {
        _createAndActivate(MARKET_ID);
        assertFalse(registry.isLive(MARKET_ID));
    }

    // ─────────────────────────────────────────────────────
    // setPendingResolution
    // ─────────────────────────────────────────────────────

    function test_setPendingResolution_happyPath() public {
        _createAndActivate(MARKET_ID);

        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.MarketPendingResolution(MARKET_ID, block.timestamp);

        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);

        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.PENDING_RESOLUTION));
        // Should be removed from active
        assertEq(registry.activeMarketCount(), 0);
    }

    function test_setPendingResolution_revert_fromListed() public {
        _createDefaultMarket();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketRegistry.MarketRegistry__InvalidStateTransition.selector,
                MARKET_ID,
                uint8(IMarketRegistry.MarketState.LISTED),
                uint8(IMarketRegistry.MarketState.PENDING_RESOLUTION)
            )
        );
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);
    }

    // ─────────────────────────────────────────────────────
    // resolveMarket
    // ─────────────────────────────────────────────────────

    function test_resolveMarket_happyPath() public {
        _createAndActivate(MARKET_ID);
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);

        uint256 extTs = block.timestamp + 1000;

        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.MarketResolved(MARKET_ID, 1, extTs);

        vm.prank(manager);
        registry.resolveMarket(MARKET_ID, 1, extTs);

        IMarketRegistry.Market memory m = registry.getMarket(MARKET_ID);
        assertEq(uint8(m.state), uint8(IMarketRegistry.MarketState.RESOLVED));
        assertEq(m.outcome, 1);
        assertEq(m.externalResolutionTime, extTs);
    }

    function test_resolveMarket_outcomeNO() public {
        _createAndActivate(MARKET_ID);
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);

        vm.prank(manager);
        registry.resolveMarket(MARKET_ID, 0, block.timestamp);

        assertEq(registry.getMarket(MARKET_ID).outcome, 0);
    }

    function test_resolveMarket_revert_fromActive() public {
        _createAndActivate(MARKET_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketRegistry.MarketRegistry__InvalidStateTransition.selector,
                MARKET_ID,
                uint8(IMarketRegistry.MarketState.ACTIVE),
                uint8(IMarketRegistry.MarketState.RESOLVED)
            )
        );
        vm.prank(manager);
        registry.resolveMarket(MARKET_ID, 1, block.timestamp);
    }

    function test_resolveMarket_revert_fromListed() public {
        _createDefaultMarket();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketRegistry.MarketRegistry__InvalidStateTransition.selector,
                MARKET_ID,
                uint8(IMarketRegistry.MarketState.LISTED),
                uint8(IMarketRegistry.MarketState.RESOLVED)
            )
        );
        vm.prank(manager);
        registry.resolveMarket(MARKET_ID, 1, block.timestamp);
    }

    // ─────────────────────────────────────────────────────
    // voidMarket
    // ─────────────────────────────────────────────────────

    function test_voidMarket_fromListed() public {
        _createDefaultMarket();

        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.MarketVoided(MARKET_ID, block.timestamp);

        vm.prank(manager);
        registry.voidMarket(MARKET_ID);

        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.VOIDED));
        assertEq(registry.getMarket(MARKET_ID).outcome, 2);
    }

    function test_voidMarket_fromActive() public {
        _createAndActivate(MARKET_ID);
        assertEq(registry.activeMarketCount(), 1);

        vm.prank(manager);
        registry.voidMarket(MARKET_ID);

        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.VOIDED));
        // Should be removed from active
        assertEq(registry.activeMarketCount(), 0);
    }

    function test_voidMarket_fromPendingResolution() public {
        _createAndActivate(MARKET_ID);
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);

        vm.prank(manager);
        registry.voidMarket(MARKET_ID);

        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.VOIDED));
    }

    function test_voidMarket_revert_fromResolved() public {
        _createAndActivate(MARKET_ID);
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);
        vm.prank(manager);
        registry.resolveMarket(MARKET_ID, 1, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketRegistry.MarketRegistry__InvalidStateTransition.selector,
                MARKET_ID,
                uint8(IMarketRegistry.MarketState.RESOLVED),
                uint8(IMarketRegistry.MarketState.VOIDED)
            )
        );
        vm.prank(manager);
        registry.voidMarket(MARKET_ID);
    }

    function test_voidMarket_revert_fromVoided() public {
        _createDefaultMarket();
        vm.prank(manager);
        registry.voidMarket(MARKET_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketRegistry.MarketRegistry__InvalidStateTransition.selector,
                MARKET_ID,
                uint8(IMarketRegistry.MarketState.VOIDED),
                uint8(IMarketRegistry.MarketState.VOIDED)
            )
        );
        vm.prank(manager);
        registry.voidMarket(MARKET_ID);
    }

    // ─────────────────────────────────────────────────────
    // updateAllocationWeight
    // ─────────────────────────────────────────────────────

    function test_updateAllocationWeight_happyPath() public {
        _createDefaultMarket();

        vm.expectEmit(true, false, false, true);
        emit IMarketRegistry.AllocationWeightUpdated(MARKET_ID, 0.5e18, 0.8e18);

        vm.prank(manager);
        registry.updateAllocationWeight(MARKET_ID, 0.8e18);

        assertEq(registry.getAllocationWeight(MARKET_ID), 0.8e18);
    }

    function test_updateAllocationWeight_revert_zeroWeight() public {
        _createDefaultMarket();

        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__InvalidAllocationWeight.selector, 0));
        vm.prank(manager);
        registry.updateAllocationWeight(MARKET_ID, 0);
    }

    function test_updateAllocationWeight_revert_aboveWAD() public {
        _createDefaultMarket();
        uint256 overWAD = WAD + 1;

        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__InvalidAllocationWeight.selector, overWAD));
        vm.prank(manager);
        registry.updateAllocationWeight(MARKET_ID, overWAD);
    }

    function test_updateAllocationWeight_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        vm.prank(manager);
        registry.updateAllocationWeight(MARKET_ID, 0.5e18);
    }

    // ─────────────────────────────────────────────────────
    // getTau
    // ─────────────────────────────────────────────────────

    function test_getTau_returnsCorrectWADHours() public {
        _createDefaultMarket();

        // At creation, tau = 30 days in hours (WAD)
        uint256 expectedHours = (30 days * WAD) / SECONDS_PER_HOUR;
        assertEq(registry.getTau(MARKET_ID), expectedHours);
    }

    function test_getTau_decreasesOverTime() public {
        _createDefaultMarket();

        uint256 tau1 = registry.getTau(MARKET_ID);

        vm.warp(block.timestamp + 10 hours);
        uint256 tau2 = registry.getTau(MARKET_ID);

        assertEq(tau1 - tau2, 10 * WAD);
    }

    function test_getTau_returnsZeroPastResolution() public {
        _createDefaultMarket();

        vm.warp(resolutionTime);
        assertEq(registry.getTau(MARKET_ID), 0);

        vm.warp(resolutionTime + 1);
        assertEq(registry.getTau(MARKET_ID), 0);
    }

    function test_getTau_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        registry.getTau(MARKET_ID);
    }

    // ─────────────────────────────────────────────────────
    // getTauMax
    // ─────────────────────────────────────────────────────

    function test_getTauMax() public {
        _createDefaultMarket();

        uint256 expectedMaxHours = (30 days * WAD) / SECONDS_PER_HOUR;
        assertEq(registry.getTauMax(MARKET_ID), expectedMaxHours);
    }

    function test_getTauMax_unchangedOverTime() public {
        _createDefaultMarket();

        uint256 tauMax1 = registry.getTauMax(MARKET_ID);
        vm.warp(block.timestamp + 10 days);
        uint256 tauMax2 = registry.getTauMax(MARKET_ID);

        assertEq(tauMax1, tauMax2);
    }

    // ─────────────────────────────────────────────────────
    // getActiveMarkets / activeMarketCount
    // ─────────────────────────────────────────────────────

    function test_activeMarkets_multipleAddRemove() public {
        // Create and activate 3 markets
        _createAndActivate(MARKET_ID);
        _createAndActivate(MARKET_ID_2);
        _createAndActivate(MARKET_ID_3);

        assertEq(registry.activeMarketCount(), 3);
        bytes32[] memory active = registry.getActiveMarkets();
        assertEq(active.length, 3);

        // Remove middle one via setPendingResolution
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID_2);

        assertEq(registry.activeMarketCount(), 2);
        active = registry.getActiveMarkets();
        assertEq(active.length, 2);
        // After swap-and-pop, MARKET_ID_3 takes MARKET_ID_2's slot
        assertEq(active[0], MARKET_ID);
        assertEq(active[1], MARKET_ID_3);
    }

    function test_activeMarkets_voidRemovesFromActive() public {
        _createAndActivate(MARKET_ID);
        assertEq(registry.activeMarketCount(), 1);

        vm.prank(manager);
        registry.voidMarket(MARKET_ID);

        assertEq(registry.activeMarketCount(), 0);
    }

    function test_activeMarkets_emptyByDefault() public {
        assertEq(registry.activeMarketCount(), 0);
        assertEq(registry.getActiveMarkets().length, 0);
    }

    // ─────────────────────────────────────────────────────
    // Access Control
    // ─────────────────────────────────────────────────────

    function test_accessControl_createMarket_onlyManager() public {
        vm.prank(nobody);
        vm.expectRevert();
        registry.createMarket(
            MARKET_ID,
            "Fail",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
    }

    function test_accessControl_activateMarket_onlyKeeper() public {
        _createDefaultMarket();

        vm.prank(nobody);
        vm.expectRevert();
        registry.activateMarket(MARKET_ID);
    }

    function test_accessControl_setLive_onlyKeeper() public {
        _createAndActivate(MARKET_ID);

        vm.prank(nobody);
        vm.expectRevert();
        registry.setLive(MARKET_ID);
    }

    function test_accessControl_setPendingResolution_onlyKeeper() public {
        _createAndActivate(MARKET_ID);

        vm.prank(nobody);
        vm.expectRevert();
        registry.setPendingResolution(MARKET_ID);
    }

    function test_accessControl_resolveMarket_onlyManager() public {
        _createAndActivate(MARKET_ID);
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);

        vm.prank(nobody);
        vm.expectRevert();
        registry.resolveMarket(MARKET_ID, 1, block.timestamp);
    }

    function test_accessControl_voidMarket_onlyManager() public {
        _createDefaultMarket();

        vm.prank(nobody);
        vm.expectRevert();
        registry.voidMarket(MARKET_ID);
    }

    function test_accessControl_updateAllocationWeight_onlyManager() public {
        _createDefaultMarket();

        vm.prank(nobody);
        vm.expectRevert();
        registry.updateAllocationWeight(MARKET_ID, 0.8e18);
    }

    // ─────────────────────────────────────────────────────
    // Pause / Unpause
    // ─────────────────────────────────────────────────────

    function test_pause_onlyAdmin() public {
        vm.prank(nobody);
        vm.expectRevert();
        registry.pause();
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        registry.pause();

        vm.prank(nobody);
        vm.expectRevert();
        registry.unpause();
    }

    function test_pause_blocksCreateMarket() public {
        vm.prank(admin);
        registry.pause();

        vm.prank(manager);
        vm.expectRevert();
        registry.createMarket(
            MARKET_ID,
            "Paused",
            "ext",
            resolutionTime,
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            0.5e18
        );
    }

    function test_pause_blocksActivate() public {
        _createDefaultMarket();

        vm.prank(admin);
        registry.pause();

        vm.prank(keeper);
        vm.expectRevert();
        registry.activateMarket(MARKET_ID);
    }

    function test_pause_blocksSetLive() public {
        _createAndActivate(MARKET_ID);

        vm.prank(admin);
        registry.pause();

        vm.prank(keeper);
        vm.expectRevert();
        registry.setLive(MARKET_ID);
    }

    function test_pause_blocksSetPendingResolution() public {
        _createAndActivate(MARKET_ID);

        vm.prank(admin);
        registry.pause();

        vm.prank(keeper);
        vm.expectRevert();
        registry.setPendingResolution(MARKET_ID);
    }

    function test_pause_blocksResolve() public {
        _createAndActivate(MARKET_ID);
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);

        vm.prank(admin);
        registry.pause();

        vm.prank(manager);
        vm.expectRevert();
        registry.resolveMarket(MARKET_ID, 1, block.timestamp);
    }

    function test_pause_blocksVoid() public {
        _createDefaultMarket();

        vm.prank(admin);
        registry.pause();

        vm.prank(manager);
        vm.expectRevert();
        registry.voidMarket(MARKET_ID);
    }

    function test_pause_blocksUpdateWeight() public {
        _createDefaultMarket();

        vm.prank(admin);
        registry.pause();

        vm.prank(manager);
        vm.expectRevert();
        registry.updateAllocationWeight(MARKET_ID, 0.8e18);
    }

    function test_unpause_resumesOperations() public {
        vm.prank(admin);
        registry.pause();

        vm.prank(admin);
        registry.unpause();

        // Should work again
        _createDefaultMarket();
        assertEq(registry.getMarket(MARKET_ID).listingTime, block.timestamp);
    }

    // ─────────────────────────────────────────────────────
    // View functions on nonexistent markets
    // ─────────────────────────────────────────────────────

    function test_getMarket_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        registry.getMarket(MARKET_ID);
    }

    function test_getMarketState_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        registry.getMarketState(MARKET_ID);
    }

    function test_isLive_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        registry.isLive(MARKET_ID);
    }

    function test_getTauMax_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        registry.getTauMax(MARKET_ID);
    }

    function test_getAllocationWeight_revert_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IMarketRegistry.MarketRegistry__MarketNotFound.selector, MARKET_ID));
        registry.getAllocationWeight(MARKET_ID);
    }

    // ─────────────────────────────────────────────────────
    // Full lifecycle
    // ─────────────────────────────────────────────────────

    function test_fullLifecycle_createToResolve() public {
        // Create
        _createDefaultMarket();
        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.LISTED));

        // Activate
        vm.prank(keeper);
        registry.activateMarket(MARKET_ID);
        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.ACTIVE));
        assertEq(registry.activeMarketCount(), 1);

        // Set live
        vm.prank(keeper);
        registry.setLive(MARKET_ID);
        assertTrue(registry.isLive(MARKET_ID));

        // Pending resolution
        vm.prank(keeper);
        registry.setPendingResolution(MARKET_ID);
        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.PENDING_RESOLUTION));
        assertEq(registry.activeMarketCount(), 0);

        // Resolve
        vm.prank(manager);
        registry.resolveMarket(MARKET_ID, 1, block.timestamp);
        assertEq(uint8(registry.getMarketState(MARKET_ID)), uint8(IMarketRegistry.MarketState.RESOLVED));
        assertEq(registry.getMarket(MARKET_ID).outcome, 1);
    }

    // ─────────────────────────────────────────────────────
    // Admin gets all roles in constructor
    // ─────────────────────────────────────────────────────

    function test_constructor_adminHasAllRoles() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.MARKET_MANAGER(), admin));
        assertTrue(registry.hasRole(registry.KEEPER(), admin));
    }

    // ─────────────────────────────────────────────────────
    // Category variants
    // ─────────────────────────────────────────────────────

    function test_createMarket_allCategories() public {
        bytes32[4] memory ids = [
            keccak256("CAT_0"),
            keccak256("CAT_1"),
            keccak256("CAT_2"),
            keccak256("CAT_3")
        ];
        IMarketRegistry.MarketCategory[4] memory cats = [
            IMarketRegistry.MarketCategory.HIGH_LIQUIDITY,
            IMarketRegistry.MarketCategory.MEDIUM_LIQUIDITY,
            IMarketRegistry.MarketCategory.LOW_LIQUIDITY,
            IMarketRegistry.MarketCategory.NEW_UNPROVEN
        ];

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(manager);
            registry.createMarket(ids[i], "Cat", "ext", resolutionTime, cats[i], 0.25e18);
            assertEq(uint8(registry.getMarket(ids[i]).category), uint8(cats[i]));
        }
    }
}
