// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CustomConsolidation {

    event BatchConsolidation(address indexed sender, address indexed targetContract, bytes sourcePubkey, bytes targetPubkey);
    event BatchSwitch(address indexed sender, address indexed targetContract, bytes sourcePubkey);
    event BatchPartialExit(address indexed sender, address indexed targetContract, bytes pubkey, bytes amount);

    modifier onlyOwner() {
        require(msg.sender == address(this), "Only the owner can call this function");
        _;
    }

    function batchConsolidation(bytes[] memory sourcePubkeys, bytes memory targetPubkey, address targetContract) external payable onlyOwner {
        require(sourcePubkeys.length >= 1, "At least one source pubkey required");

        for (uint256 i = 0; i < sourcePubkeys.length; i++) {
            require(sourcePubkeys[i].length == 48, "Invalid pubkey length");
        }
        require(targetPubkey.length == 48, "Invalid target pubkey length");

        for (uint256 i = 0; i < sourcePubkeys.length; i++) {
            bytes memory concatenated = abi.encodePacked(sourcePubkeys[i],  targetPubkey);

            (bool success, ) = targetContract.call{value: 0xb}(concatenated);
            require(success, "Call to target contract failed");
            emit BatchConsolidation(msg.sender, targetContract, sourcePubkeys[i], targetPubkey);
        }
    }

    function batchSwitch(bytes[] memory pubkeys, address targetContract) external payable onlyOwner {
        require(pubkeys.length >= 1, "At least one pubkey required");

        for (uint256 i = 0; i < pubkeys.length; i++) {
            require(pubkeys[i].length == 48, "Invalid pubkey length");
        }

        for (uint256 i = 0; i < pubkeys.length; i++) {
            bytes memory concatenated = abi.encodePacked(pubkeys[i], pubkeys[i]);
            (bool success, ) = targetContract.call{value: 0xb}(concatenated);
            require(success, "Call to target contract failed");
            emit BatchSwitch(msg.sender, targetContract, pubkeys[i]);
        }
    }

    function batchPartialExit(bytes[2][] memory data, address targetContract) external payable onlyOwner {
        require(data.length >= 1, "At least one entry required");

        for (uint256 i = 0; i < data.length; i++) {
            require(data[i][0].length == 48, "Invalid pubkey length");
            require(data[i][1].length == 8, "Amount must be 16 bytes");
        }

        for (uint256 i = 0; i < data.length; i++) {
            bytes memory concatenated = abi.encodePacked(data[i][0], data[i][1]);
            (bool success, ) = targetContract.call{value: 0x1}(concatenated);
            require(success, "Call to target contract failed");
            emit BatchPartialExit(msg.sender, targetContract, data[i][0], data[i][1]);
        }
    }
}
