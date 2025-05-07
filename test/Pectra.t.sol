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
    // Bytecode that returns a constant fee value of 1 wei
    bytes constant feeCode = hex"6001600052600160206000f3";

    // Deploy the contract and set up target addresses with "successful" code.
    function setUp() public {
        pectra = new Pectra();
        // Use fee code instead of just success code
        vm.etch(consolidationTarget, feeCode);
        vm.etch(exitTarget, feeCode);
        vm.deal(address(pectra), 100 ether);

        // Set up EOA for delegation tests
        eoa = vm.addr(EOA_PRIVATE_KEY);
        vm.deal(eoa, 100 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for getFee
    // ─────────────────────────────────────────────────────────────────────────────

    function testGetFee_ConsolidationTarget() public view {
        uint256 fee = pectra.getConsolidationFee();
        assertEq(fee, 1 wei, "Fee from consolidationTarget should be 1 wei");
    }

    function testGetFee_ExitTarget() public view {
        uint256 fee = pectra.getExitFee();
        assertEq(fee, 1 wei, "Fee from exitTarget should be 1 wei");
    }

    function testGetFee_FailedCall() public {
        // Temporarily set target to revert code
        vm.etch(consolidationTarget, revertCode);
        uint256 fee = pectra.getConsolidationFee();
        assertEq(fee, pectra.MIN_FEE(), "Fee should default to MIN_FEE when call fails");
        // Reset back to fee code
        vm.etch(consolidationTarget, feeCode);
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

    function validAmountValue(uint256 value) internal view returns (bytes memory) {
        // Returns an amount with the correct length and specified value
        bytes memory amount = new bytes(pectra.AMOUNT_LENGTH());

        // Value is expected to be in Gwei units
        // (1 ETH = 10^9 Gwei, 1 Gwei = 10^9 wei)
        // For testing purposes, we use the value directly as Gwei

        // Convert uint256 to bytes in big-endian format
        for (uint256 i = 0; i < pectra.AMOUNT_LENGTH(); i++) {
            amount[i] = bytes1(uint8(value >> (8 * (pectra.AMOUNT_LENGTH() - 1 - i))));
        }

        return amount;
    }

    function confirmFullExit() internal pure returns (bytes memory) {
        // Returns a single byte with value 1 (true) to confirm full exit
        bytes memory confirm = new bytes(1);
        confirm[0] = bytes1(uint8(1));
        return confirm;
    }

    function rejectFullExit() internal pure returns (bytes memory) {
        // Returns a single byte with value 0 (false) to reject full exit
        bytes memory reject = new bytes(1);
        reject[0] = bytes1(uint8(0));
        return reject;
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

    // Test an invalid source pubkey length emits the proper event.
    function testBatchConsolidation_InvalidSourcePubkeyLength() public {
        bytes[] memory sources = new bytes[](1);
        // Create an invalid pubkey (one byte less than required)
        sources[0] = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1);
        bytes memory target = validPubkey();
        vm.expectEmit(true, true, true, true);
        emit Pectra.ConsolidationFailed(Pectra.FailureReason.INVALID_PUBKEY_LENGTH, sources[0], target);
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
        emit Pectra.ConsolidationFailed(Pectra.FailureReason.OPERATION_FAILED, sources[0], target);
        vm.prank(address(pectra));
        pectra.batchConsolidation{value: 1}(sources, target);
        // Restore successful code.
        vm.etch(consolidationTarget, feeCode);
    }

    // Test successful execution where all calls succeed.
    function testBatchConsolidation_Success() public {
        uint256 count = 3;
        bytes[] memory sources = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            sources[i] = validPubkey();
        }
        bytes memory target = validPubkey();

        // Get the fee from the target
        uint256 fee = pectra.getConsolidationFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
        uint256 preBalance = consolidationTarget.balance;

        vm.prank(address(pectra));
        pectra.batchConsolidation{value: totalValue}(sources, target);

        // Each successful call sends fee amount
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

    function testBatchSwitch_InvalidValidatorPubkeyLength() public {
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1); // one byte less than required
        vm.expectEmit(true, true, true, true);
        emit Pectra.SwitchFailed(Pectra.FailureReason.INVALID_PUBKEY_LENGTH, pubkeys[0]);
        vm.prank(address(pectra));
        pectra.batchSwitch{value: 1}(pubkeys);
    }

    function testBatchSwitch_FailedCall() public {
        vm.etch(consolidationTarget, revertCode);
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = validPubkey();
        vm.expectEmit(true, true, true, true);
        emit Pectra.SwitchFailed(Pectra.FailureReason.OPERATION_FAILED, pubkeys[0]);
        vm.prank(address(pectra));
        pectra.batchSwitch{value: 1}(pubkeys);
        vm.etch(consolidationTarget, feeCode);
    }

    function testBatchSwitch_Success() public {
        uint256 count = 2;
        bytes[] memory pubkeys = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            pubkeys[i] = validPubkey();
        }

        // Get the fee from the target
        uint256 fee = pectra.getConsolidationFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
        uint256 preBalance = consolidationTarget.balance;

        vm.prank(address(pectra));
        pectra.batchSwitch{value: totalValue}(pubkeys);

        assertEq(consolidationTarget.balance, preBalance + totalValue);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Tests for batchELExit
    // ─────────────────────────────────────────────────────────────────────────────

    function testBatchELExit_Unauthorized() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = 0;
        data[0].isFullExit = true;
        vm.expectRevert(abi.encodeWithSelector(Pectra.Unauthorized.selector));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_EmptyData() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](0);
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.MinimumValidatorRequired.selector));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_TooManyValidators() public {
        uint256 count = pectra.MAX_VALIDATORS() + 1; // one more than allowed
        Pectra.ExitData[] memory data = new Pectra.ExitData[](count);
        for (uint256 i = 0; i < count; i++) {
            data[i].pubkey = validPubkey();
            data[i].amount = 0;
            data[i].isFullExit = true;
        }
        vm.prank(address(pectra));
        vm.expectRevert(abi.encodeWithSelector(Pectra.TooManyValidators.selector));
        pectra.batchELExit{value: count}(data);
    }

    function testBatchELExit_InvalidPublicKeyLength() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        // Invalid pubkey length (one byte less than required)
        data[0].pubkey = new bytes(pectra.VALIDATOR_PUBKEY_LENGTH() - 1);
        data[0].amount = 0;
        data[0].isFullExit = true;
        vm.expectEmit(true, true, true, true);
        emit Pectra.ExecutionLayerExitFailed(Pectra.FailureReason.INVALID_PUBKEY_LENGTH, data[0].pubkey, data[0].amount);
        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_ZeroAmountWithoutConfirmation() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = 0; // Zero amount
        data[0].isFullExit = false; // Flag set to false
        vm.expectEmit(true, true, true, true);
        emit Pectra.ExecutionLayerExitFailed(
            Pectra.FailureReason.FULL_EXIT_NOT_CONFIRMED, data[0].pubkey, data[0].amount
        );
        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_ExceedsMaximumAmount() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = pectra.MAX_WITHDRAWAL_AMOUNT() + 1;
        data[0].isFullExit = false; // Changed to false since full exit can't have amount

        vm.expectEmit(true, true, true, true);
        emit Pectra.ExecutionLayerExitFailed(
            Pectra.FailureReason.AMOUNT_EXCEEDS_MAXIMUM, data[0].pubkey, data[0].amount
        );

        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_FailedCall() public {
        vm.etch(exitTarget, revertCode);
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = 1000000000; // 1 ether in gwei
        data[0].isFullExit = false; // Changed to false since full exit can't have amount

        vm.expectEmit(true, true, true, true);
        emit Pectra.ExecutionLayerExitFailed(Pectra.FailureReason.OPERATION_FAILED, data[0].pubkey, data[0].amount);

        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
        vm.etch(exitTarget, feeCode);
    }

    function testBatchELExit_FullExitWithAmount() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = 1000000000; // 1 ether in gwei
        data[0].isFullExit = true; // Setting both amount and isFullExit

        vm.expectEmit(true, true, true, true);
        emit Pectra.ExecutionLayerExitFailed(Pectra.FailureReason.FULL_EXIT_WITH_AMOUNT, data[0].pubkey, data[0].amount);

        vm.prank(address(pectra));
        pectra.batchELExit{value: 1}(data);
    }

    function testBatchELExit_SuccessWithValidAmount() public {
        uint256 count = 2;
        Pectra.ExitData[] memory data = new Pectra.ExitData[](count);
        for (uint256 i = 0; i < count; i++) {
            data[i].pubkey = validPubkey();
            data[i].amount = 1000000000; // 1 ether in gwei
            data[i].isFullExit = false; // Changed to false since full exit can't have amount
        }

        // Get the fee from the target
        uint256 fee = pectra.getExitFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
        uint256 preBalance = exitTarget.balance;

        vm.prank(address(pectra));
        pectra.batchELExit{value: totalValue}(data);

        assertEq(exitTarget.balance, preBalance + totalValue);
    }

    function testBatchELExit_SuccessWithZeroAmount() public {
        uint256 count = 2;
        Pectra.ExitData[] memory data = new Pectra.ExitData[](count);
        for (uint256 i = 0; i < count; i++) {
            data[i].pubkey = validPubkey();
            data[i].amount = 0; // Zero amount
            data[i].isFullExit = true; // Explicitly confirm full exit
        }

        // Get the fee from the target
        uint256 fee = pectra.getExitFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
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

        // Get the fee from the target
        uint256 fee = pectra.getConsolidationFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
        uint256 preBalance = consolidationTarget.balance;

        // Call the function on the EOA address instead of the contract
        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) =
            eoa.call{value: totalValue}(abi.encodeWithSelector(Pectra.batchConsolidation.selector, sources, target));
        assertTrue(success);

        // Each successful call sends fee amount
        assertEq(consolidationTarget.balance, preBalance + totalValue);
    }

    // Test batchSwitch via delegation
    function testBatchSwitch_Delegation() public {
        uint256 count = 2;
        bytes[] memory pubkeys = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            pubkeys[i] = validPubkey();
        }

        // Get the fee from the target
        uint256 fee = pectra.getConsolidationFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
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
        Pectra.ExitData[] memory data = new Pectra.ExitData[](count);
        for (uint256 i = 0; i < count; i++) {
            data[i].pubkey = validPubkey();
            data[i].amount = 1000000000; // 1 ether in gwei
            data[i].isFullExit = false; // Changed to false since full exit can't have amount
        }

        // Get the fee from the target
        uint256 fee = pectra.getExitFee();
        assertEq(fee, 1 wei, "Fee should be 1 wei");

        uint256 totalValue = count * fee;
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
        Pectra.ExitData[] memory data = new Pectra.ExitData[](0); // Empty array should fail

        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) = eoa.call{value: 1}(abi.encodeWithSelector(Pectra.batchELExit.selector, data));
        assertFalse(success);
    }

    // Test delegation with wrong private key
    function testDelegation_WrongPrivateKey() public {
        uint256 wrongPrivateKey = 0x5678; // Different from EOA_PRIVATE_KEY
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = 1000000000; // 1 ether in gwei
        data[0].isFullExit = true;

        // Create a different EOA address from the wrong private key
        address wrongEoa = vm.addr(wrongPrivateKey);
        vm.deal(wrongEoa, 100 ether);
        vm.prank(wrongEoa);
        // Sign with the wrong private key but for the wrong EOA
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        (bool success,) = eoa.call{value: 1}(abi.encodeWithSelector(Pectra.batchELExit.selector, data));
        assertFalse(success);
    }

    // Test that delegation fails due to onlySelf modifier
    function testDelegation_FailsDueToOnlySelf() public {
        Pectra.ExitData[] memory data = new Pectra.ExitData[](1);
        data[0].pubkey = validPubkey();
        data[0].amount = 1000000000; // 1 ether in gwei
        data[0].isFullExit = true;

        vm.prank(eoa);
        vm.signAndAttachDelegation(address(pectra), EOA_PRIVATE_KEY);
        vm.expectRevert(abi.encodeWithSelector(Pectra.Unauthorized.selector));
        pectra.batchELExit{value: 1}(data);
    }
}
