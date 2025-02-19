// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
pragma abicoder v2;

contract Pectra {
    error BatchConsolidationFailed(address sender, bytes failedPubkey);
    error BatchSwitchFailed(address sender, bytes failedPubkey);
    error BatchPartialExitFailed(address sender, bytes failedPubkey);
    error InvalidPubkeyLength(bytes invalidPubkey);
    error InvalidAmountLength(bytes invalidAmount);
    
    modifier onlyOwner() {
        require(msg.sender == address(this), "Unauthorized: Must be executed by the Owner");
        _;
    }

    function batchConsolidation(bytes[] memory sourcePubkeys, bytes memory targetPubkey) 
        external payable onlyOwner
    {
        uint256 batchSize = sourcePubkeys.length;
        require(batchSize >= 1, "At least one source pubkey required");
        if (targetPubkey.length != 48) {
            revert InvalidPubkeyLength(targetPubkey);
        }

        require(msg.value >= batchSize * 1 wei, "1 wei per source validator is required");
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (sourcePubkeys[i].length != 48) {
                revert InvalidPubkeyLength(sourcePubkeys[i]);
            }

            bytes memory concatenated = abi.encodePacked(sourcePubkeys[i], targetPubkey);
            (bool success,) = address(0x01aBEa29659e5e97C95107F20bb753cD3e09bBBb).call{value: amountPerTx}(concatenated);
            if (!success) {
                revert BatchConsolidationFailed(msg.sender, sourcePubkeys[i]);
            }
        }
    }

    function batchSwitch(bytes[] memory pubkeys) 
        external payable onlyOwner
    {
        uint256 batchSize = pubkeys.length;
        require(batchSize >= 1, "At least one pubkey required");

        require(msg.value >= batchSize * 1 wei, "1 wei per validator is required");
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (pubkeys[i].length != 48) {
                revert InvalidPubkeyLength(pubkeys[i]);
            }

            bytes memory concatenated = abi.encodePacked(pubkeys[i], pubkeys[i]);
            (bool success,) = address(0x01aBEa29659e5e97C95107F20bb753cD3e09bBBb).call{value: amountPerTx}(concatenated);
            if (!success) {
                revert BatchSwitchFailed(msg.sender, pubkeys[i]);
            }
        }
    }

    function batchPartialExit(bytes[2][] memory data) 
        external payable onlyOwner
    {
        uint256 batchSize = data.length;
        require(batchSize >= 1, "At least one entry required");

        require(msg.value >= batchSize * 1 wei, "1 wei per validator is required");
        uint256 amountPerTx = msg.value / batchSize;

        for (uint256 i = 0; i < batchSize; i++) {
            if (data[i][0].length != 48) {
                revert InvalidPubkeyLength(data[i][0]);
            }
            if (data[i][1].length != 8) {
                revert InvalidAmountLength(data[i][1]);
            }

            bytes memory concatenated = abi.encodePacked(data[i][0], data[i][1]);
            (bool success,) = address(0x09Fc772D0857550724b07B850a4323f39112aAaA).call{value: amountPerTx}(concatenated);
            if (!success) {
                revert BatchPartialExitFailed(msg.sender, data[i][0]);
            }
        }
    }
}