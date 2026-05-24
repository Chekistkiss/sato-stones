// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus} from "../interfaces/IVRFCoordinatorV2Plus.sol";

/// @notice Minimal VRF coordinator mock for local/tests (supports multi-word fulfillment).
contract MockVRFCoordinator is IVRFCoordinatorV2Plus {
    uint256 public nextRequestId = 1;

    mapping(uint256 => address) public consumers;

    function requestRandomWords(RandomWordsRequest calldata req)
        external
        returns (uint256 requestId)
    {
        requestId = nextRequestId++;
        consumers[requestId] = msg.sender;
        req; // silence unused
    }

    function fulfill(uint256 requestId, uint256 randomWord) external {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        _deliver(requestId, words);
    }

    function fulfillWords(uint256 requestId, uint256 w0, uint256 w1, uint256 w2) external {
        uint256[] memory words = new uint256[](3);
        words[0] = w0;
        words[1] = w1;
        words[2] = w2;
        _deliver(requestId, words);
    }

    function _deliver(uint256 requestId, uint256[] memory words) internal {
        address consumer = consumers[requestId];
        (bool ok,) = consumer.call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, words)
        );
        require(ok, "fulfill failed");
    }
}
