// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {TestBase} from "./lib/TestBase.sol";

import {TokenVotingHats} from "../src/TokenVotingHats.sol";
import {TokenVotingSetupHats} from "../src/TokenVotingSetupHats.sol";
import {MajorityVotingBase, IMajorityVoting} from "../src/base/MajorityVotingBase.sol";
import {GovernanceERC20} from "../src/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "../src/erc20/GovernanceWrappedERC20.sol";
import {HatsMock} from "./mocks/HatsMock.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract TokenVotingHatsFlowTest is TestBase {
    address internal constant HATS_PROTOCOL = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    uint256 internal constant PROPOSER_HAT_ID = 111;
    uint256 internal constant VOTER_HAT_ID = 222;
    uint256 internal constant EXECUTOR_HAT_ID = 333;

    DAO internal dao;
    TokenVotingHats internal plugin;
    GovernanceERC20 internal governanceToken;
    TokenVotingSetupHats internal setup;

    function setUp() public {
        // Deploy Hats mock at the canonical protocol address used by HatsCondition.
        HatsMock hats = new HatsMock();
        vm.etch(HATS_PROTOCOL, address(hats).code);

        // Deploy DAO proxy with this contract as owner.
        DAO daoBase = new DAO();
        dao = DAO(
            payable(
                ProxyLib.deployUUPSProxy(
                    address(daoBase), abi.encodeCall(DAO.initialize, ("", address(this), address(0), ""))
                )
            )
        );

        // Deploy setup with base implementations.
        GovernanceERC20 governanceERC20Base = new GovernanceERC20(
            IDAO(address(0)), "Base", "BASE", GovernanceERC20.MintSettings(new address[](0), new uint256[](0), false)
        );
        GovernanceWrappedERC20 governanceWrappedERC20Base =
            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "WrappedBase", "WBASE");

        setup = new TokenVotingSetupHats(governanceERC20Base, governanceWrappedERC20Base);

        // Prepare installation parameters.
        MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.Standard,
            supportThreshold: 0,
            minParticipation: 0,
            minDuration: 1 hours,
            minProposerVotingPower: 0
        });

        TokenVotingSetupHats.TokenSettings memory tokenSettings =
            TokenVotingSetupHats.TokenSettings({addr: address(0), name: "HatToken", symbol: "HAT"});

        address[] memory receivers = new address[](3);
        receivers[0] = alice;
        receivers[1] = bob;
        receivers[2] = carol;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 10 ether;
        amounts[2] = 10 ether;

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings({receivers: receivers, amounts: amounts, ensureDelegationOnMint: true});

        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});

        TokenVotingSetupHats.HatsConfig memory hatsConfig = TokenVotingSetupHats.HatsConfig({
            proposerHatId: PROPOSER_HAT_ID,
            voterHatId: VOTER_HAT_ID,
            executorHatId: EXECUTOR_HAT_ID
        });

        bytes memory data = setup.encodeInstallationParametersHats(
            votingSettings,
            tokenSettings,
            mintSettings,
            targetConfig,
            0, // min approvals
            "",
            new address[](0),
            hatsConfig
        );

        (address pluginAddress, IPluginSetup.PreparedSetupData memory prepared) =
            setup.prepareInstallation(address(dao), data);

        plugin = TokenVotingHats(pluginAddress);
        governanceToken = GovernanceERC20(prepared.helpers[1]);

        _applyPermissions(prepared.permissions);

        // Ensure test actors having voting power by self-delegating.
        vm.prank(alice);
        governanceToken.delegate(alice);
        vm.prank(bob);
        governanceToken.delegate(bob);
        vm.prank(carol);
        governanceToken.delegate(carol);

        // Advance block and timestamp so past vote snapshots include the delegated balances.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function test_CreateProposalRequiresProposerHat() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), bob, plugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        HatsMock(HATS_PROTOCOL).setWearer(alice, PROPOSER_HAT_ID, true);

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));
        assertTrue(proposalId != 0, "proposal should succeed");
    }

    function test_VoteRequiresVoterHat() external {
        HatsMock(HATS_PROTOCOL).setWearer(alice, PROPOSER_HAT_ID, true);
        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), bob, plugin.CAST_VOTE_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        HatsMock(HATS_PROTOCOL).setWearer(bob, VOTER_HAT_ID, true);
        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        assertEq(uint8(plugin.getVoteOption(proposalId, bob)), uint8(IMajorityVoting.VoteOption.Yes));
    }

    function test_ExecuteRequiresExecutorHat() external {
        HatsMock(HATS_PROTOCOL).setWearer(alice, PROPOSER_HAT_ID, true);
        HatsMock(HATS_PROTOCOL).setWearer(alice, VOTER_HAT_ID, true);
        HatsMock(HATS_PROTOCOL).setWearer(bob, VOTER_HAT_ID, true);

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("", new Action[](0), 0, 0, bytes(""));

        vm.prank(alice);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);
        vm.prank(bob);
        plugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), bob, plugin.EXECUTE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.execute(proposalId);

        HatsMock(HATS_PROTOCOL).setWearer(carol, EXECUTOR_HAT_ID, true);
        vm.prank(carol);
        plugin.execute(proposalId);

        (, bool executed,,,) = _getProposalState(proposalId);
        assertTrue(executed, "proposal should be executed");
    }

    function _applyPermissions(PermissionLib.MultiTargetPermission[] memory permissions) internal {
        for (uint256 i = 0; i < permissions.length; i++) {
            PermissionLib.MultiTargetPermission memory perm = permissions[i];
            if (perm.operation == PermissionLib.Operation.Grant) {
                if (perm.condition == PermissionLib.NO_CONDITION) {
                    dao.grant(perm.where, perm.who, perm.permissionId);
                } else {
                    dao.grantWithCondition(
                        perm.where, perm.who, perm.permissionId, IPermissionCondition(perm.condition)
                    );
                }
            } else if (perm.operation == PermissionLib.Operation.GrantWithCondition) {
                dao.grantWithCondition(perm.where, perm.who, perm.permissionId, IPermissionCondition(perm.condition));
            } else {
                revert("unsupported operation");
            }
        }
    }

    function _getProposalState(uint256 proposalId)
        internal
        view
        returns (
            bool open,
            bool executed,
            MajorityVotingBase.ProposalParameters memory params,
            MajorityVotingBase.Tally memory tally,
            Action[] memory actions
        )
    {
        (open, executed, params, tally, actions,,) = plugin.getProposal(proposalId);
    }
}
