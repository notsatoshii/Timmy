// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { PositionManager } from "../contracts/core/PositionManager.sol";
import { IPositionManager } from "../contracts/interfaces/IPositionManager.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract PositionManagerTest is Test {
    PositionManager internal pm;

    uint256 internal constant WAD = 1e18;
    bytes32 internal constant MARKET_ID = keccak256("TEST_MARKET");
    bytes32 internal constant MARKET_ID_2 = keccak256("TEST_MARKET_2");

    address internal admin = makeAddr("admin");
    address internal engine = makeAddr("engine");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal unauthorized = makeAddr("unauthorized");

    bytes32 internal ENGINE_ROLE;

    function setUp() public {
        vm.prank(admin);
        pm = new PositionManager(admin);
        ENGINE_ROLE = pm.ENGINE();

        vm.prank(admin);
        pm.grantRole(ENGINE_ROLE, engine);
    }

    // ─────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────

    function _createDefaultPosition(address owner, bytes32 marketId, bool isLong)
        internal
        returns (uint256)
    {
        vm.prank(engine);
        return pm.createPosition(
            owner,
            marketId,
            isLong,
            50 * WAD / 100,   // entryPI = 0.50
            51 * WAD / 100,   // entryPrice = 0.51
            1000 * WAD,       // positionSize
            100 * WAD,        // collateral
            10 * WAD,         // leverage = 10x
            WAD,              // borrowIndex
            int256(WAD)       // fundingIndex
        );
    }

    // ─────────────────────────────────────────────────
    // createPosition
    // ─────────────────────────────────────────────────

    function test_createPosition_happyPath() public {
        vm.prank(engine);
        uint256 id = pm.createPosition(
            alice, MARKET_ID, true,
            50 * WAD / 100, 51 * WAD / 100,
            1000 * WAD, 100 * WAD, 10 * WAD,
            WAD, int256(WAD)
        );

        assertEq(id, 1, "first position ID should be 1");

        IPositionManager.Position memory pos = pm.getPosition(id);
        assertEq(pos.id, 1);
        assertEq(pos.owner, alice);
        assertEq(pos.marketId, MARKET_ID);
        assertTrue(pos.isLong);
        assertEq(pos.entryPI, 50 * WAD / 100);
        assertEq(pos.entryPrice, 51 * WAD / 100);
        assertEq(pos.positionSize, 1000 * WAD);
        assertEq(pos.collateral, 100 * WAD);
        assertEq(pos.leverage, 10 * WAD);
        assertEq(pos.borrowIndex, WAD);
        assertEq(pos.fundingIndex, int256(WAD));
        assertEq(pos.openTimestamp, block.timestamp);
        assertTrue(pos.isOpen);
    }

    function test_createPosition_incrementingIds() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(alice, MARKET_ID, false);
        uint256 id3 = _createDefaultPosition(bob, MARKET_ID, true);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
    }

    function test_createPosition_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IPositionManager.PositionCreated(
            1, MARKET_ID, alice, true,
            50 * WAD / 100, 51 * WAD / 100,
            1000 * WAD, 100 * WAD, 10 * WAD,
            block.timestamp
        );

        vm.prank(engine);
        pm.createPosition(
            alice, MARKET_ID, true,
            50 * WAD / 100, 51 * WAD / 100,
            1000 * WAD, 100 * WAD, 10 * WAD,
            WAD, int256(WAD)
        );
    }

    // ─────────────────────────────────────────────────
    // closePosition
    // ─────────────────────────────────────────────────

    function test_closePosition_happyPath() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(engine);
        pm.closePosition(id);

        assertFalse(pm.isPositionOpen(id));
    }

    function test_closePosition_emitsEvent() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.expectEmit(true, true, true, true);
        emit IPositionManager.PositionClosed(id, block.timestamp);

        vm.prank(engine);
        pm.closePosition(id);
    }

    function test_closePosition_revertsIfNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.PositionManager__PositionNotFound.selector, 999)
        );
        vm.prank(engine);
        pm.closePosition(999);
    }

    function test_closePosition_revertsIfAlreadyClosed() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(engine);
        pm.closePosition(id);

        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.PositionManager__PositionNotOpen.selector, id)
        );
        vm.prank(engine);
        pm.closePosition(id);
    }

    // ─────────────────────────────────────────────────
    // updateCollateral
    // ─────────────────────────────────────────────────

    function test_updateCollateral_happyPath() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(engine);
        pm.updateCollateral(id, 200 * WAD);

        IPositionManager.Position memory pos = pm.getPosition(id);
        assertEq(pos.collateral, 200 * WAD);
    }

    function test_updateCollateral_emitsEvent() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.expectEmit(true, true, true, true);
        emit IPositionManager.PositionCollateralUpdated(id, 100 * WAD, 200 * WAD);

        vm.prank(engine);
        pm.updateCollateral(id, 200 * WAD);
    }

    function test_updateCollateral_revertsIfNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.PositionManager__PositionNotFound.selector, 999)
        );
        vm.prank(engine);
        pm.updateCollateral(999, 200 * WAD);
    }

    function test_updateCollateral_revertsIfClosed() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(engine);
        pm.closePosition(id);

        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.PositionManager__PositionNotOpen.selector, id)
        );
        vm.prank(engine);
        pm.updateCollateral(id, 200 * WAD);
    }

    // ─────────────────────────────────────────────────
    // View functions
    // ─────────────────────────────────────────────────

    function test_getPosition_revertsIfNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.PositionManager__PositionNotFound.selector, 42)
        );
        pm.getPosition(42);
    }

    function test_isPositionOpen_returnsFalseForNonexistent() public view {
        assertFalse(pm.isPositionOpen(42));
    }

    function test_isPositionOpen_trueWhenOpen() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);
        assertTrue(pm.isPositionOpen(id));
    }

    function test_isPositionOpen_falseWhenClosed() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);
        vm.prank(engine);
        pm.closePosition(id);
        assertFalse(pm.isPositionOpen(id));
    }

    function test_getPositionOwner_happyPath() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);
        assertEq(pm.getPositionOwner(id), alice);
    }

    function test_getPositionOwner_revertsIfNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPositionManager.PositionManager__PositionNotFound.selector, 42)
        );
        pm.getPositionOwner(42);
    }

    function test_getUserPositions_empty() public view {
        uint256[] memory ids = pm.getUserPositions(alice);
        assertEq(ids.length, 0);
    }

    function test_getUserPositions_multiplePositions() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(alice, MARKET_ID, false);
        uint256 id3 = _createDefaultPosition(alice, MARKET_ID_2, true);

        uint256[] memory ids = pm.getUserPositions(alice);
        assertEq(ids.length, 3);
        assertEq(ids[0], id1);
        assertEq(ids[1], id2);
        assertEq(ids[2], id3);
    }

    function test_getMarketPositions_empty() public view {
        uint256[] memory ids = pm.getMarketPositions(MARKET_ID);
        assertEq(ids.length, 0);
    }

    function test_getMarketPositions_multiplePositions() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(bob, MARKET_ID, false);

        uint256[] memory ids = pm.getMarketPositions(MARKET_ID);
        assertEq(ids.length, 2);
        assertEq(ids[0], id1);
        assertEq(ids[1], id2);
    }

    function test_getMarketSidePositions_empty() public view {
        uint256[] memory ids = pm.getMarketSidePositions(MARKET_ID, true);
        assertEq(ids.length, 0);
    }

    function test_getMarketSidePositions_separatesSides() public {
        uint256 longId = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 shortId = _createDefaultPosition(bob, MARKET_ID, false);

        uint256[] memory longs = pm.getMarketSidePositions(MARKET_ID, true);
        assertEq(longs.length, 1);
        assertEq(longs[0], longId);

        uint256[] memory shorts = pm.getMarketSidePositions(MARKET_ID, false);
        assertEq(shorts.length, 1);
        assertEq(shorts[0], shortId);
    }

    // ─────────────────────────────────────────────────
    // totalOpenPositions
    // ─────────────────────────────────────────────────

    function test_totalOpenPositions_incrementsOnCreate() public {
        assertEq(pm.totalOpenPositions(), 0);

        _createDefaultPosition(alice, MARKET_ID, true);
        assertEq(pm.totalOpenPositions(), 1);

        _createDefaultPosition(bob, MARKET_ID, false);
        assertEq(pm.totalOpenPositions(), 2);
    }

    function test_totalOpenPositions_decrementsOnClose() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        _createDefaultPosition(bob, MARKET_ID, false);
        assertEq(pm.totalOpenPositions(), 2);

        vm.prank(engine);
        pm.closePosition(id1);
        assertEq(pm.totalOpenPositions(), 1);
    }

    // ─────────────────────────────────────────────────
    // nextPositionId
    // ─────────────────────────────────────────────────

    function test_nextPositionId_startsAt1() public view {
        assertEq(pm.nextPositionId(), 1);
    }

    function test_nextPositionId_incrementsAfterCreate() public {
        _createDefaultPosition(alice, MARKET_ID, true);
        assertEq(pm.nextPositionId(), 2);

        _createDefaultPosition(alice, MARKET_ID, false);
        assertEq(pm.nextPositionId(), 3);
    }

    // ─────────────────────────────────────────────────
    // Swap-and-pop array tracking on close
    // ─────────────────────────────────────────────────

    function test_close_removesFromUserPositions_swapAndPop() public {
        // Create 3 positions for alice: ids 1, 2, 3
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(alice, MARKET_ID, false);
        uint256 id3 = _createDefaultPosition(alice, MARKET_ID, true);

        // Close the first one (id1). Last element (id3) swaps into index 0
        vm.prank(engine);
        pm.closePosition(id1);

        uint256[] memory ids = pm.getUserPositions(alice);
        assertEq(ids.length, 2);
        assertEq(ids[0], id3);
        assertEq(ids[1], id2);
    }

    function test_close_removesFromMarketPositions_swapAndPop() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(bob, MARKET_ID, false);
        uint256 id3 = _createDefaultPosition(alice, MARKET_ID, true);

        // Close id2 (middle). id3 should swap into its slot
        vm.prank(engine);
        pm.closePosition(id2);

        uint256[] memory ids = pm.getMarketPositions(MARKET_ID);
        assertEq(ids.length, 2);
        assertEq(ids[0], id1);
        assertEq(ids[1], id3);
    }

    function test_close_removesFromMarketSidePositions_swapAndPop() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(bob, MARKET_ID, true);
        uint256 id3 = _createDefaultPosition(alice, MARKET_ID, true);

        // Close id1 (first). id3 swaps in
        vm.prank(engine);
        pm.closePosition(id1);

        uint256[] memory longs = pm.getMarketSidePositions(MARKET_ID, true);
        assertEq(longs.length, 2);
        assertEq(longs[0], id3);
        assertEq(longs[1], id2);
    }

    function test_close_lastElement_noSwapNeeded() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 id2 = _createDefaultPosition(alice, MARKET_ID, true);

        // Close last element (id2). No swap, just pop
        vm.prank(engine);
        pm.closePosition(id2);

        uint256[] memory ids = pm.getUserPositions(alice);
        assertEq(ids.length, 1);
        assertEq(ids[0], id1);
    }

    function test_close_onlyElement_arrayBecomesEmpty() public {
        uint256 id1 = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(engine);
        pm.closePosition(id1);

        uint256[] memory userIds = pm.getUserPositions(alice);
        assertEq(userIds.length, 0);

        uint256[] memory marketIds = pm.getMarketPositions(MARKET_ID);
        assertEq(marketIds.length, 0);

        uint256[] memory sideIds = pm.getMarketSidePositions(MARKET_ID, true);
        assertEq(sideIds.length, 0);
    }

    function test_multipleUsers_multipleMarkets_independentTracking() public {
        // Alice: 2 positions in MARKET_ID, 1 in MARKET_ID_2
        uint256 a1 = _createDefaultPosition(alice, MARKET_ID, true);
        uint256 a2 = _createDefaultPosition(alice, MARKET_ID, false);
        uint256 a3 = _createDefaultPosition(alice, MARKET_ID_2, true);

        // Bob: 1 position in MARKET_ID
        uint256 b1 = _createDefaultPosition(bob, MARKET_ID, true);

        assertEq(pm.getUserPositions(alice).length, 3);
        assertEq(pm.getUserPositions(bob).length, 1);
        assertEq(pm.getMarketPositions(MARKET_ID).length, 3); // a1, a2, b1
        assertEq(pm.getMarketPositions(MARKET_ID_2).length, 1); // a3
        assertEq(pm.getMarketSidePositions(MARKET_ID, true).length, 2); // a1, b1
        assertEq(pm.getMarketSidePositions(MARKET_ID, false).length, 1); // a2
        assertEq(pm.totalOpenPositions(), 4);

        // Close a2 (alice's short on MARKET_ID)
        vm.prank(engine);
        pm.closePosition(a2);

        assertEq(pm.getUserPositions(alice).length, 2);
        assertEq(pm.getMarketPositions(MARKET_ID).length, 2);
        assertEq(pm.getMarketSidePositions(MARKET_ID, false).length, 0);
        assertEq(pm.totalOpenPositions(), 3);

        // Close b1
        vm.prank(engine);
        pm.closePosition(b1);

        assertEq(pm.getUserPositions(bob).length, 0);
        assertEq(pm.getMarketPositions(MARKET_ID).length, 1); // only a1
        assertEq(pm.getMarketSidePositions(MARKET_ID, true).length, 1); // only a1
        assertEq(pm.totalOpenPositions(), 2);

        // Remaining positions still accessible
        IPositionManager.Position memory pos = pm.getPosition(a1);
        assertTrue(pos.isOpen);
        pos = pm.getPosition(a3);
        assertTrue(pos.isOpen);
    }

    // ─────────────────────────────────────────────────
    // Access Control
    // ─────────────────────────────────────────────────

    function test_createPosition_revertsWithoutEngineRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                ENGINE_ROLE
            )
        );
        vm.prank(unauthorized);
        pm.createPosition(
            alice, MARKET_ID, true,
            50 * WAD / 100, 51 * WAD / 100,
            1000 * WAD, 100 * WAD, 10 * WAD,
            WAD, int256(WAD)
        );
    }

    function test_closePosition_revertsWithoutEngineRole() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                ENGINE_ROLE
            )
        );
        vm.prank(unauthorized);
        pm.closePosition(id);
    }

    function test_updateCollateral_revertsWithoutEngineRole() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                ENGINE_ROLE
            )
        );
        vm.prank(unauthorized);
        pm.updateCollateral(id, 200 * WAD);
    }

    // ─────────────────────────────────────────────────
    // Pause / Unpause
    // ─────────────────────────────────────────────────

    function test_pause_blocksCreatePosition() public {
        vm.prank(admin);
        pm.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(engine);
        pm.createPosition(
            alice, MARKET_ID, true,
            50 * WAD / 100, 51 * WAD / 100,
            1000 * WAD, 100 * WAD, 10 * WAD,
            WAD, int256(WAD)
        );
    }

    function test_pause_blocksClosePosition() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(admin);
        pm.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(engine);
        pm.closePosition(id);
    }

    function test_pause_blocksUpdateCollateral() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(admin);
        pm.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(engine);
        pm.updateCollateral(id, 200 * WAD);
    }

    function test_pause_viewFunctionsStillWork() public {
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);

        vm.prank(admin);
        pm.pause();

        // Views should not revert
        pm.getPosition(id);
        pm.isPositionOpen(id);
        pm.getPositionOwner(id);
        pm.getUserPositions(alice);
        pm.getMarketPositions(MARKET_ID);
        pm.getMarketSidePositions(MARKET_ID, true);
        pm.totalOpenPositions();
        pm.nextPositionId();
    }

    function test_unpause_restoresOperations() public {
        vm.prank(admin);
        pm.pause();

        vm.prank(admin);
        pm.unpause();

        // Should succeed after unpause
        uint256 id = _createDefaultPosition(alice, MARKET_ID, true);
        assertEq(id, 1);
    }

    function test_pause_revertsForNonAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                pm.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorized);
        pm.pause();
    }

    function test_unpause_revertsForNonAdmin() public {
        vm.prank(admin);
        pm.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                pm.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(unauthorized);
        pm.unpause();
    }
}
