// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IHats} from "../../src/interfaces/IHats.sol";

/// @notice Toy Hats Protocol mock used in tests.
contract HatsMock is IHats {
    mapping(uint256 => mapping(address => bool)) private wearers;

    function setWearer(address wearer, uint256 hatId, bool hasHat) external {
        wearers[hatId][wearer] = hasHat;
    }

    function isWearerOfHat(address wearer, uint256 hatId) external view override returns (bool) {
        return wearers[hatId][wearer];
    }
}
