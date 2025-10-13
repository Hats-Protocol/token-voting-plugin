// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

/// @notice Minimal interface for the Hats Protocol used by this plugin.
interface IHats {
    /// @notice Checks if a wearer currently holds a specific hat.
    function isWearerOfHat(address _wearer, uint256 _hatId) external view returns (bool);
}
