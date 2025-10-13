// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {TokenVoting, MajorityVotingBase} from "./TokenVoting.sol";

/// @title TokenVotingHats
/// @notice Token voting plugin variant that relies on Hats-based permission conditions.
contract TokenVotingHats is TokenVoting {
    /// @notice Permission identifier required to cast votes.
    bytes32 public constant CAST_VOTE_PERMISSION_ID = keccak256("CAST_VOTE_PERMISSION");

    /// @inheritdoc TokenVoting
    function initialize(
        IDAO _dao,
        MajorityVotingBase.VotingSettings calldata _votingSettings,
        IVotesUpgradeable _token,
        IPlugin.TargetConfig calldata _targetConfig,
        uint256 _minApprovals,
        bytes calldata _pluginMetadata,
        address[] memory _excludedAccounts
    ) public override {
        super.initialize(
            _dao, _votingSettings, _token, _targetConfig, _minApprovals, _pluginMetadata, _excludedAccounts
        );
    }

    /// @inheritdoc MajorityVotingBase
    function vote(uint256 _proposalId, VoteOption _voteOption, bool _tryEarlyExecution)
        public
        override
        auth(CAST_VOTE_PERMISSION_ID)
    {
        super.vote(_proposalId, _voteOption, _tryEarlyExecution);
    }
}
