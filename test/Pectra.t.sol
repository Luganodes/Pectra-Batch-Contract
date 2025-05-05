// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Pectra.sol";

contract PectraTest is Test {
    Pectra public pectra;

    // Add a private key for delegation testing
    uint256 constant EOA_PRIVATE_KEY = 0x1234; // Example private key
    address eoa;

    // These addresses are hardcoded in the Pectra contract.
    address constant consolidationTarget = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;
    address constant exitTarget = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    // Minimal bytecode that immediately returns (i.e. succeeds).
    bytes constant successCode = hex"60006000f3";
    // Minimal bytecode that reverts.
    bytes constant revertCode = hex"6000fd";

    // Deploy the contract and set up target addresses with "successful" code.
    function setUp() public {
        pectra = new Pectra();
        vm.etch(consolidationTarget, successCode);
        vm.etch(exitTarget, successCode);
        vm.deal(address(pectra), 100 ether);

        // Set up EOA for delegation tests
        eoa = vm.addr(EOA_PRIVATE_KEY);
        vm.deal(eoa, 100 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Utility functions for valid-length data.
    // ─────────────────────────────────────────────────────────────────────────────
    function validPubkey() internal view returns (bytes memory) {
        // Returns a pubkey with the correct length (all zeroes)
        return new bytes(pectra.VALIDATOR_PUBKEY_LENGTH());
    }

    function validAmount() internal view returns (bytes memory) {
        // Returns an amount with the correct length (all zeroes)
        return new bytes(pectra.AMOUNT_LENGTH());
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for batchConsolidation
    // ─────────────────────────────────────────────────────────────────────────────

    // Test that calling without the contract itself as sender reverts.
    function testBatchConsolidation_Unauthorized() public {
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        bytes memory target = validPubkey();
        vm.expectRevert(abi.encodeWithSelector(Pectra.Unauthorized.selector));
        pectra.batchConsolidation{value: 1}(sources, target);
    }

    // Test empty source array reverts.
    function testBatchConsolidation_EmptySources() public {
        bytes[] memory sources = new bytes[](0);
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.MinimumValidatorRequired.selector));
        pectra.batchConsolidation{value: 1}(sources, target);
    }

    // Test exceeding maximum number of source validators.
    function testBatchConsolidation_TooManySources() public {
        uint256 count = pectra.MAX_SOURCE_VALIDATORS() + 1; // one more than allowed
        bytes[] memory sources = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            sources[i] = validPubkey();
        }
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.TooManySourceValidators.selector));
        pectra.batchConsolidation{value: count}(sources, target);
    }

    // Test that an invalid target pubkey length reverts using the custom error.
    function testBatchConsolidation_InvalidTargetLength() public {
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        // Provide an invalid target pubkey (one byte less than required)
        bytes memory invalidTarget = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1);
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.InvalidTargetPubkeyLength.selector, invalidTarget));
        pectra.batchConsolidation{value: 1}(sources, invalidTarget);
    }

    // Test msg.value not divisible by the number of source validators.
    function testBatchConsolidation_MsgValueNotDivisible() public {
        bytes[] memory sources = new bytes[](2);
        sources[0] = validPubkey();
        sources[1] = validPubkey();
        bytes memory target = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.ValueNotDivisibleByValidators.selector));
        pectra.batchConsolidation{value: 3}(sources, target); // 3 wei not divisible by 2
    }

    // Test an invalid source pubkey length emits the proper event.
    function testBatchConsolidation_InvalidSourcePubkeyLength() public {
        bytes[] memory sources = new bytes[](1);
        // Create an invalid pubkey (one byte less than required)
        sources[0] = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1);
        bytes memory target = validPubkey();
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.INVALID_PUBKEY_LENGTH();
        emit Pectra.ConsolidationFailed(reasonCode, sources[0], target);
        vm.prank(address(pectra));
        pectra.batchConsolidation{value: 1}(sources, target);
    }

    // Test when the call to consolidationTarget fails (simulate via revert code).
    function testBatchConsolidation_FailedCall() public {
        // Simulate failure on consolidationTarget.
        vm.etch(consolidationTarget, revertCode);
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        bytes memory target = validPubkey();
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.OPERATION_FAILED();
        emit Pectra.ConsolidationFailed(reasonCode, sources[0], target);
        vm.prank(address(pectra));
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
        vm.expectRevert(abi.encodeWithSelector(Pectra.Unauthorized.selector));
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_EmptyValidators() public {
        bytes[] memory pubkeys = new bytes[](0);
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.MinimumValidatorRequired.selector));
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_TooManyValidators() public {
        uint256 count = pectra.MAX_VALIDATORS() + 1; // one more than allowed
        bytes[] memory pubkeys = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            pubkeys[i] = validPubkey();
        }
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.TooManyValidators.selector));
        pectra.batchSwitch{value: count}(pubkeys);
    }

    function testBatchSwitch_MsgValueNotDivisible() public {
        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validPubkey();
        pubkeys[1] = validPubkey();
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.ValueNotDivisibleByValidators.selector));
        pectra.batchSwitch{value: 3}(pubkeys);
    }

    function testBatchSwitch_InvalidValidatorPubkeyLength() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1); // one byte less than required
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.INVALID_PUBKEY_LENGTH();
        emit Pectra.SwitchFailed(reasonCode, pubkeys[0]);
        vm.prank(address(pectra));
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_FailedCall() public {
        vm.etch(consolidationTarget, revertCode);
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validPubkey();
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.OPERATION_FAILED();
        emit Pectra.SwitchFailed(reasonCode, pubkeys[0]);
        vm.prank(address(pectra));
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
        vm.expectRevert(abi.encodeWithSelector(Pectra.Unauthorized.selector));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_EmptyData() public {
        bytes[2][] memory data = new bytes[2][](0);
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.MinimumValidatorRequired.selector));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_TooManyValidators() public {
        uint256 count = pectra.MAX_VALIDATORS() + 1; // one more than allowed
        bytes[2][] memory data = new bytes[2][](count);
        for (uint256 i = 0; i < count; i++) {
            data[i][0] = validPubkey();
            data[i][1] = validAmount();
        }
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.TooManyValidators.selector));
        pectra.batchELExit{value: count}(data);
    }

    function testBatchELExit_MsgValueNotDivisible() public {
        bytes[2][] memory data = new bytes[2][](2);
        for (uint256 i = 0; i < 2; i++) {
            data[i][0] = validPubkey();
            data[i][1] = validAmount();
        }
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.ValueNotDivisibleByValidators.selector));
        pectra.batchELExit{value: 3}(data);
    }

    function testBatchELExit_InvalidPublicKeyLength() public {
        bytes[2][] memory data = new bytes[2][](1);
        // Invalid pubkey length (one byte less than required)
        data[0][0] = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1);
        data[0][1] = validAmount();
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.INVALID_PUBKEY_LENGTH();
        emit Pectra.ExecutionLayerExitFailed(reasonCode, data[0][0], data[0][1]);
        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_InvalidAmountLength() public {
        bytes[2][] memory data = new bytes[2][](1);
        data[0][0] = validPubkey();
        // Invalid amount length (one byte less than required)
        data[0][1] = new bytes(pectra.AMOUNT_LENGTH() - 1);
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.INVALID_AMOUNT_LENGTH();
        emit Pectra.ExecutionLayerExitFailed(reasonCode, data[0][0], data[0][1]);
        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_FailedCall() public {
        vm.etch(exitTarget, revertCode);
        bytes[2][] memory data = new bytes[2][](1);
        data[0][0] = validPubkey();
        data[0][1] = validAmount();
        vm.expectEmit(true, true, true, true);
        uint8 reasonCode = pectra.OPERATION_FAILED();
        emit Pectra.ExecutionLayerExitFailed(reasonCode, data[0][0], data[0][1]);
        vm.prank(address(pectra));
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

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for EIP-7702 Delegation
    // ─────────────────────────────────────────────────────────────────────────────

    // Test batchConsolidation via delegation
    function testBatchConsolidation_Delegation() public {
        uint256 count = 3;
        bytes[] memory sources = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            sources[i] = validPubkey();
        }
        bytes memory target = validPubkey();
        uint256 totalValue = count; // 1 wei per call
        uint256 preBalance = consolidationTarget.balance;

        // Call the function on the EOA address instead of the contract
        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) =
            eoa.call{value: totalValue}(abi.encodeWithSelector(Pectra.batchConsolidation.selector, sources, target));
        assertTrue(success);

        // Each successful call sends 1 wei
        assertEq(consolidationTarget.balance, preBalance + totalValue);
    }

    // Test batchSwitch via delegation
    function testBatchSwitch_Delegation() public {
        uint256 count = 2;
        bytes[] memory pubkeys = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            pubkeys[i] = validPubkey();
        }
        uint256 totalValue = count; // 1 wei each
        uint256 preBalance = consolidationTarget.balance;

        // Call the function on the EOA address instead of the contract
        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) = eoa.call{value: totalValue}(abi.encodeWithSelector(Pectra.batchSwitch.selector, pubkeys));
        assertTrue(success);

        assertEq(consolidationTarget.balance, preBalance + totalValue);
    }

    // Test batchELExit via delegation
    function testBatchELExit_Delegation() public {
        uint256 count = 2;
        bytes[2][] memory data = new bytes[2][](count);
        for (uint256 i = 0; i < count; i++) {
            data[i][0] = validPubkey();
            data[i][1] = validAmount();
        }
        uint256 totalValue = count; // 1 wei per entry
        uint256 preBalance = exitTarget.balance;

        // Call the function on the EOA address instead of the contract
        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) = eoa.call{value: totalValue}(abi.encodeWithSelector(Pectra.batchELExit.selector, data));
        assertTrue(success);

        assertEq(exitTarget.balance, preBalance + totalValue);
    }

    // Test delegation with invalid parameters
    function testDelegation_InvalidParameters() public {
        bytes[] memory sources = new bytes[](0); // Empty array should fail
        bytes memory target = validPubkey();

        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) =
            eoa.call{value: 1}(abi.encodeWithSelector(Pectra.batchConsolidation.selector, sources, target));
        assertFalse(success);
    }

    // Test delegation with wrong value
    function testDelegation_WrongValue() public {
        bytes[] memory pubkeys = new bytes[](2);
        pubkeys[0] = validPubkey();
        pubkeys[1] = validPubkey();

        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) = eoa.call{value: 3}(abi.encodeWithSelector(Pectra.batchSwitch.selector, pubkeys));
        assertFalse(success); // 3 wei not divisible by 2
    }

    // Test delegation with wrong private key
    function testDelegation_WrongPrivateKey() public {
        uint256 wrongPrivateKey = 0x5678; // Different from EOA_PRIVATE_KEY
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        bytes memory target = validPubkey();

        // Create a different EOA address from the wrong private key
        address wrongEoa = vm.addr(wrongPrivateKey);
        vm.deal(wrongEoa, 100 ether);
        vm.prank(wrongEoa);
        // Sign with the wrong private key but for the wrong EOA
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) =
            eoa.call{value: 1}(abi.encodeWithSelector(Pectra.batchConsolidation.selector, sources, target));
        assertFalse(success);
    }

    // Test that delegation fails due to onlySelf modifier
    function testDelegation_FailsDueToOnlySelf() public {
        bytes[] memory sources = new bytes[](1);
        sources[0] = validPubkey();
        bytes memory target = validPubkey();

        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        vm.expectRevert(abi.encodeWithSelector(Pectra.Unauthorized.selector));
        pectra.batchConsolidation{value: 1}(sources, target);
    }
}
