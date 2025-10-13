// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {TestBase} from "./lib/TestBase.sol";
import {SimpleBuilder} from "./builders/SimpleBuilder.sol";

import {TokenVotingSetupHats} from "../src/TokenVotingSetupHats.sol";
import {TokenVotingHats} from "../src/TokenVotingHats.sol";
import {HatsCondition} from "../src/condition/HatsCondition.sol";
import {MajorityVotingBase} from "../src/base/MajorityVotingBase.sol";
import {GovernanceERC20} from "../src/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "../src/erc20/GovernanceWrappedERC20.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract TokenVotingSetupHatsTest is TestBase {
    bytes32 internal constant UPDATE_VOTING_SETTINGS_PERMISSION_ID = keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");
    bytes32 internal constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 internal constant CAST_VOTE_PERMISSION_ID = keccak256("CAST_VOTE_PERMISSION");
    bytes32 internal constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");
    bytes32 internal constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");
    bytes32 internal constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    address internal constant ANY_ADDR = address(type(uint160).max);

    TokenVotingSetupHats internal pluginSetup;
    GovernanceERC20 internal governanceERC20Base;
    GovernanceWrappedERC20 internal governanceWrappedERC20Base;
    TokenVotingHats internal tokenVotingImplementation;
    IDAO internal dao;

    MajorityVotingBase.VotingSettings internal defaultVotingSettings;
    TokenVotingSetupHats.TokenSettings internal defaultTokenSettings;
    GovernanceERC20.MintSettings internal defaultMintSettings;
    IPlugin.TargetConfig internal defaultTargetConfig;
    uint256 internal defaultMinApproval;
    bytes internal defaultMetadata;
    address[] internal defaultExcludedAccounts;
    TokenVotingSetupHats.HatsConfig internal defaultHatsConfig;

    function setUp() public {
        (dao,,,) = new SimpleBuilder().withDaoOwner(address(this)).build();

        governanceERC20Base = new GovernanceERC20(
            IDAO(address(0)),
            "GovernanceToken",
            "GT",
            GovernanceERC20.MintSettings(new address[](0), new uint256[](0), false)
        );
        governanceWrappedERC20Base = new GovernanceWrappedERC20(IERC20Upgradeable(address(0x1)), "WrappedToken", "WT");

        pluginSetup = new TokenVotingSetupHats(governanceERC20Base, governanceWrappedERC20Base);
        tokenVotingImplementation = TokenVotingHats(pluginSetup.implementation());

        defaultVotingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
            supportThreshold: 500_000,
            minParticipation: 200_000,
            minDuration: 1 hours,
            minProposerVotingPower: 0
        });
        defaultTokenSettings = TokenVotingSetupHats.TokenSettings({addr: address(0), name: "MyToken", symbol: "HAT"});
        defaultMintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0),
            ensureDelegationOnMint: false
        });
        defaultTargetConfig = IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
        defaultMinApproval = 300_000;
        defaultMetadata = hex"11";
        defaultExcludedAccounts = new address[](0);
        defaultHatsConfig = TokenVotingSetupHats.HatsConfig({proposerHatId: 111, voterHatId: 222, executorHatId: 333});
    }

    function _assertPermission(
        PermissionLib.MultiTargetPermission memory p,
        PermissionLib.Operation op,
        address where,
        address who,
        address condition,
        bytes32 permissionId
    ) internal pure {
        assertEq(uint8(p.operation), uint8(op), "permission op mismatch");
        assertEq(p.where, where, "permission where mismatch");
        assertEq(p.who, who, "permission who mismatch");
        assertEq(p.condition, condition, "permission condition mismatch");
        assertEq(p.permissionId, permissionId, "permissionId mismatch");
    }

    function testHarnessInitialized() external view {
        assertEq(pluginSetup.governanceERC20Base(), address(governanceERC20Base));
        assertEq(pluginSetup.governanceWrappedERC20Base(), address(governanceWrappedERC20Base));
        assertEq(address(tokenVotingImplementation), pluginSetup.implementation());
    }

    function test_WhenEncodingAndDecodingInstallationParameters_ThenDataRoundTrips() external view {
        bytes memory data = pluginSetup.encodeInstallationParametersHats(
            defaultVotingSettings,
            defaultTokenSettings,
            defaultMintSettings,
            defaultTargetConfig,
            defaultMinApproval,
            defaultMetadata,
            defaultExcludedAccounts,
            defaultHatsConfig
        );

        TokenVotingSetupHats.InstallationParameters memory decoded =
            pluginSetup.decodeInstallationParametersHats(data);

        assertEq(uint8(decoded.votingSettings.votingMode), uint8(defaultVotingSettings.votingMode));
        assertEq(decoded.votingSettings.supportThreshold, defaultVotingSettings.supportThreshold);
        assertEq(decoded.votingSettings.minParticipation, defaultVotingSettings.minParticipation);
        assertEq(decoded.votingSettings.minDuration, defaultVotingSettings.minDuration);
        assertEq(decoded.votingSettings.minProposerVotingPower, defaultVotingSettings.minProposerVotingPower);

        assertEq(decoded.tokenSettings.addr, defaultTokenSettings.addr);
        assertEq(decoded.tokenSettings.name, defaultTokenSettings.name);
        assertEq(decoded.tokenSettings.symbol, defaultTokenSettings.symbol);

        assertEq(decoded.mintSettings.ensureDelegationOnMint, defaultMintSettings.ensureDelegationOnMint);
        assertEq(decoded.mintSettings.receivers.length, defaultMintSettings.receivers.length);
        assertEq(decoded.mintSettings.amounts.length, defaultMintSettings.amounts.length);

        assertEq(decoded.targetConfig.target, defaultTargetConfig.target);
        assertEq(uint8(decoded.targetConfig.operation), uint8(defaultTargetConfig.operation));

        assertEq(decoded.minApprovals, defaultMinApproval);
        assertEq(decoded.pluginMetadata, defaultMetadata);
        assertEq(decoded.excludedAccounts.length, defaultExcludedAccounts.length);

        assertEq(decoded.hatsConfig.proposerHatId, defaultHatsConfig.proposerHatId);
        assertEq(decoded.hatsConfig.voterHatId, defaultHatsConfig.voterHatId);
        assertEq(decoded.hatsConfig.executorHatId, defaultHatsConfig.executorHatId);
    }

    function test_WhenPreparingInstallation_ThenHelpersAndPermissionsAreConfigured() external {
        bytes memory data = pluginSetup.encodeInstallationParametersHats(
            defaultVotingSettings,
            defaultTokenSettings,
            defaultMintSettings,
            defaultTargetConfig,
            defaultMinApproval,
            defaultMetadata,
            defaultExcludedAccounts,
            defaultHatsConfig
        );

        (address plugin, IPluginSetup.PreparedSetupData memory prepared) =
            pluginSetup.prepareInstallation(address(dao), data);

        assertTrue(plugin != address(0), "plugin not deployed");
        assertEq(prepared.helpers.length, 2, "helpers length");
        assertEq(prepared.permissions.length, 8, "permissions length");

        HatsCondition condition = HatsCondition(prepared.helpers[0]);
        assertEq(condition.hatForPermission(CREATE_PROPOSAL_PERMISSION_ID), defaultHatsConfig.proposerHatId);
        assertEq(condition.hatForPermission(CAST_VOTE_PERMISSION_ID), defaultHatsConfig.voterHatId);
        assertEq(condition.hatForPermission(EXECUTE_PROPOSAL_PERMISSION_ID), defaultHatsConfig.executorHatId);

        assertEq(prepared.helpers[1], address(TokenVotingHats(plugin).getVotingToken()), "voting token helper mismatch");

        _assertPermission(
            prepared.permissions[0],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            UPDATE_VOTING_SETTINGS_PERMISSION_ID
        );
        _assertPermission(
            prepared.permissions[1],
            PermissionLib.Operation.Grant,
            address(dao),
            plugin,
            PermissionLib.NO_CONDITION,
            EXECUTE_PERMISSION_ID
        );
        _assertPermission(
            prepared.permissions[2],
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            ANY_ADDR,
            address(condition),
            CREATE_PROPOSAL_PERMISSION_ID
        );
        _assertPermission(
            prepared.permissions[3],
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            ANY_ADDR,
            address(condition),
            CAST_VOTE_PERMISSION_ID
        );
        _assertPermission(
            prepared.permissions[4],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            SET_TARGET_CONFIG_PERMISSION_ID
        );
        _assertPermission(
            prepared.permissions[5],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            SET_METADATA_PERMISSION_ID
        );
        _assertPermission(
            prepared.permissions[6],
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            ANY_ADDR,
            address(condition),
            EXECUTE_PROPOSAL_PERMISSION_ID
        );

        bytes32 mintPermission = GovernanceERC20(prepared.helpers[1]).MINT_PERMISSION_ID();
        _assertPermission(
            prepared.permissions[7],
            PermissionLib.Operation.Grant,
            prepared.helpers[1],
            address(dao),
            PermissionLib.NO_CONDITION,
            mintPermission
        );
    }

    function test_GivenExistingTokenWhenPreparingInstallation_ThenTokenIsWrapped() external {
        ERC20Mock underlyingToken = new ERC20Mock("Mock", "MCK");
        defaultTokenSettings.addr = address(underlyingToken);

        bytes memory data = pluginSetup.encodeInstallationParametersHats(
            defaultVotingSettings,
            defaultTokenSettings,
            defaultMintSettings,
            defaultTargetConfig,
            defaultMinApproval,
            defaultMetadata,
            defaultExcludedAccounts,
            defaultHatsConfig
        );

        (address plugin, IPluginSetup.PreparedSetupData memory prepared) =
            pluginSetup.prepareInstallation(address(dao), data);

        assertTrue(plugin != address(0), "plugin not deployed");

        address votingToken = address(TokenVotingHats(plugin).getVotingToken());
        assertTrue(votingToken != address(underlyingToken), "token should be wrapped when IVotes missing");
        assertEq(prepared.helpers[1], votingToken, "helper mismatch");
    }

    function test_WhenExecutorHatSentinelUsed_ThenExecutionPermissionIsPublic() external {
        defaultHatsConfig.executorHatId = 1;

        bytes memory data = pluginSetup.encodeInstallationParametersHats(
            defaultVotingSettings,
            defaultTokenSettings,
            defaultMintSettings,
            defaultTargetConfig,
            defaultMinApproval,
            defaultMetadata,
            defaultExcludedAccounts,
            defaultHatsConfig
        );

        (, IPluginSetup.PreparedSetupData memory prepared) =
            pluginSetup.prepareInstallation(address(dao), data);

        HatsCondition condition = HatsCondition(prepared.helpers[0]);
        assertTrue(
            condition.hatForPermission(EXECUTE_PROPOSAL_PERMISSION_ID) == 1,
            "sentinel should be stored as executor hat"
        );
    }
}
