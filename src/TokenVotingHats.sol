// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {TokenVoting, MajorityVotingBase} from "./TokenVoting.sol";

/// @title TokenVotingHats
/// @notice Token voting plugin variant that relies on Hats-based permission conditions.
/// @dev v1.0 (Release 1, Build 1). However, to support inheritence from TokenVoting (which is on Build 4), the initializer version of this contract is set to 3.
contract TokenVotingHats is TokenVoting {
    /// @notice Permission identifier required to cast votes.
    bytes32 public constant CAST_VOTE_PERMISSION_ID = keccak256("CAST_VOTE_PERMISSION");

    /// @inheritdoc MajorityVotingBase
    function vote(uint256 _proposalId, VoteOption _voteOption, bool _tryEarlyExecution)
        public
        override
        auth(CAST_VOTE_PERMISSION_ID)
    {
        super.vote(_proposalId, _voteOption, _tryEarlyExecution);
    }
}
