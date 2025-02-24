// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Pectra {
    address public immutable consolidationTarget =
        0x01aBEa29659e5e97C95107F20bb753cD3e09bBBb;
    address public immutable exitTarget =
        0x09Fc772D0857550724b07B850a4323f39112aAaA;
    event ConsolidationFailed(
        string message,
        address sender,
        bytes failedPubkey
    );
    event SwitchFailed(string message, address sender, bytes failedPubkey);
    event ExecutionLayerExitFailed(
        string message,
        address sender,
        bytes pubkey,
        bytes amount
    );
    error InvalidTargetPubkeyLength(bytes invalidTargetPubkey);

    modifier onlySelf() {
        require(
            msg.sender == address(this),
            "Unauthorized: Must be executed by the Owner"
        );
        _;
    }

    function batchConsolidation(
        bytes[] memory sourcePubkeys,
        bytes memory targetPubkey
    ) external payable onlySelf {
        uint256 batchSize = sourcePubkeys.length;
        require(batchSize >= 1, "At least one source validator required");
        require(
            batchSize <= 63,
            "Number of source validators must be less than 64, since Max EB is 2048 ETH"
        );
        if (targetPubkey.length != 48) {
            revert InvalidTargetPubkeyLength(targetPubkey);
        }
        require(
            msg.value % batchSize == 0,
            "msg.value must be divisible by length of source validators"
        );
        require(
            msg.value >= batchSize * 1 wei,
            "1 wei per source validator is required"
        );
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (sourcePubkeys[i].length != 48) {
                emit ConsolidationFailed(
                    "Invalid source validator public key length",
                    msg.sender,
                    sourcePubkeys[i]
                );
                continue;
            }

            bytes memory concatenated = abi.encodePacked(
                sourcePubkeys[i],
                targetPubkey
            );
            (bool success, ) = consolidationTarget.call{value: amountPerTx}(
                concatenated
            );
            if (!success) {
                emit ConsolidationFailed(
                    "Consolidation failed",
                    msg.sender,
                    sourcePubkeys[i]
                );
                continue;
            }
        }
    }

    function batchSwitch(bytes[] memory pubkeys) external payable onlySelf {
        uint256 batchSize = pubkeys.length;
        require(batchSize >= 1, "At least one validator required");
        require(batchSize <= 200, "Number of validators must be less than 200");
        require(
            msg.value % batchSize == 0,
            "msg.value must be divisible by length of validators"
        );
        require(
            msg.value >= batchSize * 1 wei,
            "1 wei per validator is required"
        );
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (pubkeys[i].length != 48) {
                emit SwitchFailed(
                    "Invalid validator public key length",
                    msg.sender,
                    pubkeys[i]
                );
                continue;
            }

            bytes memory concatenated = abi.encodePacked(
                pubkeys[i],
                pubkeys[i]
            );
            (bool success, ) = consolidationTarget.call{value: amountPerTx}(
                concatenated
            );
            if (!success) {
                emit SwitchFailed("Switch failed", msg.sender, pubkeys[i]);
                continue;
            }
        }
    }

    function batchELExit(bytes[2][] memory data) external payable onlySelf {
        uint256 batchSize = data.length;
        require(batchSize >= 1, "At least one entry required");
        require(batchSize <= 200, "Number of validators must be less than 200");
        require(
            msg.value % batchSize == 0,
            "msg.value must be divisible by length of validators"
        );
        require(
            msg.value >= batchSize * 1 wei,
            "1 wei per validator is required"
        );
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (data[i][0].length != 48) {
                emit ExecutionLayerExitFailed(
                    "Invalid validator public key length",
                    msg.sender,
                    data[i][0],
                    data[i][1]
                );
                continue;
            }
            if (data[i][1].length != 8) {
                emit ExecutionLayerExitFailed(
                    "Invalid amount length",
                    msg.sender,
                    data[i][0],
                    data[i][1]
                );
                continue;
            }

            bytes memory concatenated = abi.encodePacked(
                data[i][0],
                data[i][1]
            );
            (bool success, ) = exitTarget.call{value: amountPerTx}(concatenated);
            if (!success) {
                emit ExecutionLayerExitFailed(
                    "Execution layer exit failed",
                    msg.sender,
                    data[i][0],
                    data[i][1]
                );
                continue;
            }
        }
    }
}
