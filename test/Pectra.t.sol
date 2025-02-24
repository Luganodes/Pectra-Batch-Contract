// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Pectra.sol";

contract PectraTest is Test {
    Pectra public pectra;

    // These addresses are hardcoded in the Pectra contract.
    address constant consolidationTarget =
        0x01aBEa29659e5e97C95107F20bb753cD3e09bBBb;
    address constant exitTarget = 0x09Fc772D0857550724b07B850a4323f39112aAaA;

    // Minimal bytecode that immediately returns (i.e. succeeds).
    bytes constant successCode = hex"60006000f3";
    // Minimal bytecode that reverts.
    bytes constant revertCode = hex"6000fd";

    // Deploy the contract and set up target addresses with “successful” code.
    function setUp() public {
        pectra = new Pectra();
        vm.etch(consolidationTarget, successCode);
        vm.etch(exitTarget, successCode);
        vm.deal(address(pectra), 100 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Utility functions for valid-length data.
    // ─────────────────────────────────────────────────────────────────────────────
    function validPubkey() internal pure returns (bytes memory) {
        // Returns a 48-byte array (all zeroes).
        return new bytes(48);
    }

    function validAmount() internal pure returns (bytes memory) {
        // Returns an 8-byte array (all zeroes).
        return new bytes(8);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for batchConsolidation
    // ─────────────────────────────────────────────────────────────────────────────

    // Test that calling without the contract itself as sender reverts.
    function testBatchConsolidation_Unauthorized() public {
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        bytes memory target = validPubkey();
        vm.expectRevert("Unauthorized: Must be executed by the Owner");
        pectra.batchConsolidation{value: 1}(sources, target);
    }

    // Test empty source array reverts.
    function testBatchConsolidation_EmptySources() public {
        bytes[] memory sources = new bytes[](0);
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert("At least one source validator required");
        pectra.batchConsolidation{value: 1}(sources, target);
    }

    // Test exceeding maximum number of source validators.
    function testBatchConsolidation_TooManySources() public {
        uint256 count = 64; // must be <= 63
        bytes[] memory sources = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            sources[i] = validPubkey();
        }
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert(
            "Number of source validators must be less than 64, since Max EB is 2048 ETH"
        );
        pectra.batchConsolidation{value: count}(sources, target);
    }

    // Test that an invalid target pubkey length reverts using the custom error.
    function testBatchConsolidation_InvalidTargetLength() public {
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        // Provide an invalid target pubkey (47 bytes instead of 48)
        bytes memory invalidTarget = new bytes(47);
        vm.prank(address(pectra));
        vm.expectRevert(
            abi.encodeWithSelector(
                Pectra.InvalidTargetPubkeyLength.selector,
                invalidTarget
            )
        );
        pectra.batchConsolidation{value: 1}(sources, invalidTarget);
    }

    // Test msg.value not divisible by the number of source validators.
    function testBatchConsolidation_MsgValueNotDivisible() public {
        bytes[] memory sources = new bytes[](2);
        sources[0] = validPubkey();
        sources[1] = validPubkey();
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert(
            "msg.value must be divisible by length of source validators"
        );
        pectra.batchConsolidation{value: 3}(sources, target); // 3 wei not divisible by 2
    }

    // Test an invalid source pubkey length emits the proper event.
    function testBatchConsolidation_InvalidSourcePubkeyLength() public {
        bytes[] memory sources = new bytes[](1);
        // Create an invalid pubkey (47 bytes)
        sources[0] = new bytes(47);
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.ConsolidationFailed(
            "Invalid source validator public key length",
            address(pectra),
            sources[0]
        );
        pectra.batchConsolidation{value: 1}(sources, target);
    }

    // Test when the call to consolidationTarget fails (simulate via revert code).
    function testBatchConsolidation_FailedCall() public {
        // Simulate failure on consolidationTarget.
        vm.etch(consolidationTarget, revertCode);
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.ConsolidationFailed(
            "Consolidation failed",
            address(pectra),
            sources[0]
        );
        pectra.batchConsolidation{value: 1}(sources, target);
        // Restore successful code.
        vm.etch(consolidationTarget, successCode);
    }

    // Test successful execution where all calls succeed.
    function testBatchConsolidation_Success() public {
        uint256 count = 3;
        bytes[] memory sources = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            sources[i] = validPubkey();
        }
        bytes memory target = validPubkey();
        uint256 totalValue = count; // 1 wei per call
        uint256 preBalance = consolidationTarget.balance;
        vm.prank(address(pectra));
        pectra.batchConsolidation{value: totalValue}(sources, target);
        // Each successful call sends 1 wei.
        assertEq(consolidationTarget.balance, preBalance + totalValue);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for batchSwitch
    // ─────────────────────────────────────────────────────────────────────────────

    function testBatchSwitch_Unauthorized() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validPubkey();
        vm.expectRevert("Unauthorized: Must be executed by the Owner");
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_EmptyValidators() public {
        bytes[] memory pubkeys = new bytes[](0);
        vm.prank(address(pectra));
        vm.expectRevert("At least one validator required");
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_TooManyValidators() public {
        uint256 count = 201;
        bytes[] memory pubkeys = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            pubkeys[i] = validPubkey();
        }
        vm.prank(address(pectra));
        vm.expectRevert("Number of validators must be less than 200");
        pectra.batchSwitch{value: count}(pubkeys);
    }

    function testBatchSwitch_MsgValueNotDivisible() public {
        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validPubkey();
        pubkeys[1] = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert("msg.value must be divisible by length of validators");
        pectra.batchSwitch{value: 3}(pubkeys);
    }

    function testBatchSwitch_InvalidValidatorPubkeyLength() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = new bytes(47);
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.SwitchFailed(
            "Invalid validator public key length",
            address(pectra),
            pubkeys[0]
        );
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_FailedCall() public {
        vm.etch(consolidationTarget, revertCode);
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validPubkey();
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.SwitchFailed("Switch failed", address(pectra), pubkeys[0]);
        pectra.batchSwitch{value: 1}(pubkeys);
        vm.etch(consolidationTarget, successCode);
    }

    function testBatchSwitch_Success() public {
        uint256 count = 2;
        bytes[] memory pubkeys = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            pubkeys[i] = validPubkey();
        }
        uint256 totalValue = count; // 1 wei each
        uint256 preBalance = consolidationTarget.balance;
        vm.prank(address(pectra));
        pectra.batchSwitch{value: totalValue}(pubkeys);
        assertEq(consolidationTarget.balance, preBalance + totalValue);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for batchELExit
    // ─────────────────────────────────────────────────────────────────────────────

    function testBatchELExit_Unauthorized() public {
        bytes[2][] memory data = new bytes[2][](1);
        data[0][0] = validPubkey();
        data[0][1] = validAmount();
        vm.expectRevert("Unauthorized: Must be executed by the Owner");
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_EmptyData() public {
        bytes[2][] memory data = new bytes[2][](0);
        vm.prank(address(pectra));
        vm.expectRevert("At least one entry required");
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_TooManyValidators() public {
        uint256 count = 201;
        bytes[2][] memory data = new bytes[2][](count);
        for (uint256 i = 0; i < count; i++) {
            data[i][0] = validPubkey();
            data[i][1] = validAmount();
        }
        vm.prank(address(pectra));
        vm.expectRevert("Number of validators must be less than 200");
        pectra.batchELExit{value: count}(data);
    }

    function testBatchELExit_MsgValueNotDivisible() public {
        bytes[2][] memory data = new bytes[2][](2);
        for (uint256 i = 0; i < 2; i++) {
            data[i][0] = validPubkey();
            data[i][1] = validAmount();
        }
        vm.prank(address(pectra));
        vm.expectRevert("msg.value must be divisible by length of validators");
        pectra.batchELExit{value: 3}(data);
    }

    function testBatchELExit_InvalidPublicKeyLength() public {
        bytes[2][] memory data = new bytes[2][](1);
        // Invalid pubkey length (47 bytes)
        data[0][0] = new bytes(47);
        data[0][1] = validAmount();
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.ExecutionLayerExitFailed(
            "Invalid validator public key length",
            address(pectra),
            data[0][0],
            data[0][1]
        );
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_InvalidAmountLength() public {
        bytes[2][] memory data = new bytes[2][](1);
        data[0][0] = validPubkey();
        // Invalid amount length (7 bytes instead of 8)
        data[0][1] = new bytes(7);
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.ExecutionLayerExitFailed(
            "Invalid amount length",
            address(pectra),
            data[0][0],
            data[0][1]
        );
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_FailedCall() public {
        vm.etch(exitTarget, revertCode);
        bytes[2][] memory data = new bytes[2][](1);
        data[0][0] = validPubkey();
        data[0][1] = validAmount();
        vm.prank(address(pectra));
        vm.expectEmit(false, false, false, true);
        emit Pectra.ExecutionLayerExitFailed(
            "Execution layer exit failed",
            address(pectra),
            data[0][0],
            data[0][1]
        );
        pectra.batchELExit{value: 1}(data);
        vm.etch(exitTarget, successCode);
    }

    function testBatchELExit_Success() public {
        uint256 count = 2;
        bytes[2][] memory data = new bytes[2][](count);
        for (uint256 i = 0; i < count; i++) {
            data[i][0] = validPubkey();
            data[i][1] = validAmount();
        }
        uint256 totalValue = count; // 1 wei per entry
        uint256 preBalance = exitTarget.balance;
        vm.prank(address(pectra));
        pectra.batchELExit{value: totalValue}(data);
        assertEq(exitTarget.balance, preBalance + totalValue);
    }
}
