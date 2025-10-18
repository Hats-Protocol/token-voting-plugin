// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IHats} from "../interfaces/IHats.sol";

import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @title HatsCondition
/// @notice Permission condition that authorizes calls based on configured Hats wearers.
contract HatsCondition is PermissionCondition {
    /// @dev Sentinel value that bypasses the hat check when used.
    uint256 internal constant PUBLIC_SENTINEL = uint256(1);

    /// @notice The permission identifiers that can be checked through this condition.
    bytes32 internal constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 internal constant CAST_VOTE_PERMISSION_ID = keccak256("CAST_VOTE_PERMISSION");
    bytes32 internal constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice Hats protocol contract consulted for membership checks.
    IHats private constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137);

    /// @notice Mapping from permission identifier to the hat id that must be worn.
    mapping(bytes32 => uint256) public hatForPermission;

    /// @param _proposerHatId Hat required to create proposals.
    /// @param _voterHatId Hat required to cast votes.
    /// @param _executorHatId Hat required to execute proposals.
    constructor(uint256 _proposerHatId, uint256 _voterHatId, uint256 _executorHatId) {
        hatForPermission[CREATE_PROPOSAL_PERMISSION_ID] = _proposerHatId;
        hatForPermission[CAST_VOTE_PERMISSION_ID] = _voterHatId;
        hatForPermission[EXECUTE_PROPOSAL_PERMISSION_ID] = _executorHatId;
    }

    /// @inheritdoc IPermissionCondition
    function isGranted(address, /* _where */ address _who, bytes32 _permissionId, bytes calldata /* _data */ )
        public
        view
        override
        returns (bool)
    {
        uint256 hatId = hatForPermission[_permissionId];

        if (hatId == PUBLIC_SENTINEL) {
            return true;
        }

        if (hatId == 0) {
            return false;
        }

        return HATS.isWearerOfHat(_who, hatId);
    }
}
