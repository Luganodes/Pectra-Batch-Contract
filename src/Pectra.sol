// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Pectra {
    address public constant consolidationTarget = 0x0000BBdDc7CE488642fb579F8B00f3a590007251;
    address public constant exitTarget = 0x00000961Ef480Eb55e80D19ad83579A64c007002;

    // Constants for validator-related parameters
    /// @dev The expected length of a validator public key in bytes
    uint256 public constant VALIDATOR_PUBKEY_LENGTH = 48;
    /// @dev The expected length of an amount value in bytes for EL exit
    uint256 public constant AMOUNT_LENGTH = 8;
    /// @dev Minimum number of validators required for batch operations
    uint256 public constant MIN_VALIDATORS = 1;
    /// @dev Maximum number of source validators allowed in consolidation,
    uint256 public constant MAX_SOURCE_VALIDATORS = 63;
    /// @dev Maximum number of validators allowed in switch and EL exit operations
    uint256 public constant MAX_VALIDATORS = 200;
    /// @dev Minimum fee required per validator
    uint256 public constant MIN_FEE = 1 wei;
    /// @dev Maximum withdrawal amount as a uint64 (representing 2048 ether in gwei)
    uint64 public constant MAX_WITHDRAWAL_AMOUNT = 0x1DCD6500000;

    // Failure reason codes
    uint8 public constant INVALID_PUBKEY_LENGTH = 1;
    uint8 public constant OPERATION_FAILED = 2;
    uint8 public constant INVALID_AMOUNT_LENGTH = 3;
    uint8 public constant INVALID_AMOUNT_VALUE = 4;
    uint8 public constant FULL_EXIT_NOT_CONFIRMED = 5;
    uint8 public constant AMOUNT_EXCEEDS_MAXIMUM = 6;

    event ConsolidationFailed(uint8 reasonCode, bytes sourcePubkey, bytes targetPubkey);
    event SwitchFailed(uint8 reasonCode, bytes pubkey);
    event ExecutionLayerExitFailed(uint8 reasonCode, bytes pubkey, bytes amount);

    error Unauthorized();
    error InvalidTargetPubkeyLength(bytes invalidTargetPubkey);
    error MinimumValidatorRequired();
    error TooManySourceValidators();
    error TooManyValidators();
    error InsufficientFeePerValidator();

    receive() external payable {}
    fallback() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), Unauthorized());
        _;
    }

    function getConsolidationFee() public view returns (uint256 fee) {
        (bool readOK, bytes memory feeData) = consolidationTarget.staticcall("");
        if (!readOK) return MIN_FEE;
        fee = uint256(bytes32(feeData));
    }

    function getExitFee() public view returns (uint256 fee) {
        (bool readOK, bytes memory feeData) = exitTarget.staticcall("");
        if (!readOK) return MIN_FEE;
        fee = uint256(bytes32(feeData));
    }

    function batchConsolidation(bytes[] calldata sourcePubkeys, bytes calldata targetPubkey)
        external
        payable
        onlySelf
    {
        uint256 batchSize = sourcePubkeys.length;
        require(batchSize >= MIN_VALIDATORS, MinimumValidatorRequired());
        require(batchSize <= MAX_SOURCE_VALIDATORS, TooManySourceValidators());
        if (targetPubkey.length != VALIDATOR_PUBKEY_LENGTH) {
            revert InvalidTargetPubkeyLength(targetPubkey);
        }

        uint256 consolidationFee = getConsolidationFee();
        require(msg.value >= batchSize * consolidationFee, InsufficientFeePerValidator());

        for (uint256 i = 0; i < batchSize; ++i) {
            if (sourcePubkeys[i].length != VALIDATOR_PUBKEY_LENGTH) {
                emit ConsolidationFailed(INVALID_PUBKEY_LENGTH, sourcePubkeys[i], targetPubkey);
                continue;
            }

            bytes memory concatenated = abi.encodePacked(sourcePubkeys[i], targetPubkey);
            (bool success,) = consolidationTarget.call{value: consolidationFee}(concatenated);
            if (!success) {
                emit ConsolidationFailed(OPERATION_FAILED, sourcePubkeys[i], targetPubkey);
                continue;
            }
        }
    }

    function batchSwitch(bytes[] calldata pubkeys) external payable onlySelf {
        uint256 batchSize = pubkeys.length;
        require(batchSize >= MIN_VALIDATORS, MinimumValidatorRequired());
        require(batchSize <= MAX_VALIDATORS, TooManyValidators());

        uint256 switchFee = getConsolidationFee();
        require(msg.value >= batchSize * switchFee, InsufficientFeePerValidator());

        for (uint256 i = 0; i < batchSize; ++i) {
            if (pubkeys[i].length != VALIDATOR_PUBKEY_LENGTH) {
                emit SwitchFailed(INVALID_PUBKEY_LENGTH, pubkeys[i]);
                continue;
            }

            bytes memory concatenated = abi.encodePacked(pubkeys[i], pubkeys[i]);
            (bool success,) = consolidationTarget.call{value: switchFee}(concatenated);
            if (!success) {
                emit SwitchFailed(OPERATION_FAILED, pubkeys[i]);
                continue;
            }
        }
    }

    // Define the ExitData struct
    struct ExitData {
        bytes pubkey; // 48-byte validator public key
        uint64 amount; // Amount in gwei (or zero for full exit)
        bool isFullExit; // Safety flag requiring explicit confirmation for full exits
    }

    function batchELExit(ExitData[] calldata data) external payable onlySelf {
        uint256 batchSize = data.length;
        require(batchSize >= MIN_VALIDATORS, MinimumValidatorRequired());
        require(batchSize <= MAX_VALIDATORS, TooManyValidators());

        uint256 exitFee = getExitFee();
        require(msg.value >= batchSize * exitFee, InsufficientFeePerValidator());

        for (uint256 i = 0; i < batchSize; ++i) {
            if (data[i].pubkey.length != VALIDATOR_PUBKEY_LENGTH) {
                emit ExecutionLayerExitFailed(INVALID_PUBKEY_LENGTH, data[i].pubkey, abi.encodePacked(data[i].amount));
                continue;
            }

            bool isZeroAmount = data[i].amount == 0;

            if (isZeroAmount && !data[i].isFullExit) {
                emit ExecutionLayerExitFailed(FULL_EXIT_NOT_CONFIRMED, data[i].pubkey, abi.encodePacked(data[i].amount));
                continue;
            }

            if (!isZeroAmount && data[i].amount > MAX_WITHDRAWAL_AMOUNT) {
                emit ExecutionLayerExitFailed(AMOUNT_EXCEEDS_MAXIMUM, data[i].pubkey, abi.encodePacked(data[i].amount));
                continue;
            }

            bytes memory amountBytes = abi.encodePacked(data[i].amount);

            bytes memory concatenated = abi.encodePacked(data[i].pubkey, amountBytes);
            (bool success,) = exitTarget.call{value: exitFee}(concatenated);
            if (!success) {
                emit ExecutionLayerExitFailed(OPERATION_FAILED, data[i].pubkey, amountBytes);
                continue;
            }
        }
    }
}
