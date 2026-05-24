// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Chainlink VRF v2.5 consumer base (routes coordinator callbacks).
abstract contract VRFConsumerBaseV2Plus {
    address private immutable _vrfCoordinator;

    constructor(address vrfCoordinator) {
        _vrfCoordinator = vrfCoordinator;
    }

    /// @dev Called by the VRF coordinator (or mock) with random words.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != _vrfCoordinator) revert OnlyVRFCoordinator();
        _fulfillRandomWords(requestId, randomWords);
    }

    function _fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;

    error OnlyVRFCoordinator();
}
