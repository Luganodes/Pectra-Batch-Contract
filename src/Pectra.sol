// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Pectra {
    address public immutable consolidationTarget = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;
    address public immutable exitTarget = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    // Constants for validator-related parameters
    /// @dev The expected length of a validator public key in bytes
    uint256 public constant VALIDATOR_PUBKEY_LENGTH = 48;
    /// @dev The expected length of an amount value in bytes for EL exit
    uint256 public constant AMOUNT_LENGTH = 8;
    /// @dev Minimum number of validators required for batch operations
    uint256 public constant MIN_VALIDATORS = 1;
    /// @dev Maximum number of source validators allowed in consolidation
    uint256 public constant MAX_SOURCE_VALIDATORS = 63;
    /// @dev Maximum number of validators allowed in switch and EL exit operations
    uint256 public constant MAX_VALIDATORS = 200;
    /// @dev Minimum value required per validator in wei
    uint256 public constant MIN_VALUE_PER_VALIDATOR = 1 wei;

    event ConsolidationFailed(string message, address sender, bytes failedPubkey);
    event SwitchFailed(string message, address sender, bytes failedPubkey);
    event ExecutionLayerExitFailed(string message, address sender, bytes pubkey, bytes amount);

    error InvalidTargetPubkeyLength(bytes invalidTargetPubkey);
    error Unauthorized();
    error MinimumValidatorRequired();
    error TooManySourceValidators();
    error TooManyValidators();
    error ValueNotDivisibleByValidators();
    error InsufficientValuePerValidator();

    modifier onlySelf() {
        require(msg.sender == address(this), Unauthorized());
        _;
    }

    function batchConsolidation(bytes[] memory sourcePubkeys, bytes memory targetPubkey) external payable onlySelf {
        uint256 batchSize = sourcePubkeys.length;
        require(batchSize >= MIN_VALIDATORS, MinimumValidatorRequired());
        require(batchSize <= MAX_SOURCE_VALIDATORS, TooManySourceValidators());
        if (targetPubkey.length != VALIDATOR_PUBKEY_LENGTH) {
            revert InvalidTargetPubkeyLength(targetPubkey);
        }
        require(msg.value % batchSize == 0, ValueNotDivisibleByValidators());
        require(msg.value >= batchSize * MIN_VALUE_PER_VALIDATOR, InsufficientValuePerValidator());
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (sourcePubkeys[i].length != VALIDATOR_PUBKEY_LENGTH) {
                emit ConsolidationFailed("Invalid source validator public key length", msg.sender, sourcePubkeys[i]);
                continue;
            }

            bytes memory concatenated = abi.encodePacked(sourcePubkeys[i], targetPubkey);
            (bool success,) = consolidationTarget.call{value: amountPerTx}(concatenated);
            if (!success) {
                emit ConsolidationFailed("Consolidation failed", msg.sender, sourcePubkeys[i]);
                continue;
            }
        }
    }

    function batchSwitch(bytes[] memory pubkeys) external payable onlySelf {
        uint256 batchSize = pubkeys.length;
        require(batchSize >= MIN_VALIDATORS, MinimumValidatorRequired());
        require(batchSize <= MAX_VALIDATORS, TooManyValidators());
        require(msg.value % batchSize == 0, ValueNotDivisibleByValidators());
        require(msg.value >= batchSize * MIN_VALUE_PER_VALIDATOR, InsufficientValuePerValidator());
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (pubkeys[i].length != VALIDATOR_PUBKEY_LENGTH) {
                emit SwitchFailed("Invalid validator public key length", msg.sender, pubkeys[i]);
                continue;
            }

            bytes memory concatenated = abi.encodePacked(pubkeys[i], pubkeys[i]);
            (bool success,) = consolidationTarget.call{value: amountPerTx}(concatenated);
            if (!success) {
                emit SwitchFailed("Switch failed", msg.sender, pubkeys[i]);
                continue;
            }
        }
    }

    function batchELExit(bytes[2][] memory data) external payable onlySelf {
        uint256 batchSize = data.length;
        require(batchSize >= MIN_VALIDATORS, MinimumValidatorRequired());
        require(batchSize <= MAX_VALIDATORS, TooManyValidators());
        require(msg.value % batchSize == 0, ValueNotDivisibleByValidators());
        require(msg.value >= batchSize * MIN_VALUE_PER_VALIDATOR, InsufficientValuePerValidator());
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (data[i][0].length != VALIDATOR_PUBKEY_LENGTH) {
                emit ExecutionLayerExitFailed("Invalid validator public key length", msg.sender, data[i][0], data[i][1]);
                continue;
            }
            if (data[i][1].length != AMOUNT_LENGTH) {
                emit ExecutionLayerExitFailed("Invalid amount length", msg.sender, data[i][0], data[i][1]);
                continue;
            }

            bytes memory concatenated = abi.encodePacked(data[i][0], data[i][1]);
            (bool success,) = exitTarget.call{value: amountPerTx}(concatenated);
            if (!success) {
                emit ExecutionLayerExitFailed("Execution layer exit failed", msg.sender, data[i][0], data[i][1]);
                continue;
            }
        }
    }
}
