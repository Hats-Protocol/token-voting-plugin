// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {GovernanceERC20} from "./erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "./erc20/GovernanceWrappedERC20.sol";
import {TokenVotingHats} from "./TokenVotingHats.sol";
import {HatsCondition} from "./condition/HatsCondition.sol";
import {MajorityVotingBase} from "./base/MajorityVotingBase.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";

import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

/// @title TokenVotingSetupHats
/// @notice Plugin setup contract for the Hats-gated TokenVoting variant.
contract TokenVotingSetupHats is PluginUpgradeableSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    uint16 internal constant THIS_BUILD = 1;

    bytes32 private constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 private constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");
    bytes32 private constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");
    bytes32 private constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");
    bytes32 private constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    address private constant ANY_ADDR = address(type(uint160).max);

    /// @notice The Hats-aware TokenVoting implementation used for proxy deployments.
    TokenVotingHats private immutable tokenVotingHatsBase;

    /// @notice Address of the GovernanceERC20 implementation used for token cloning.
    address public immutable governanceERC20Base;

    /// @notice Address of the GovernanceWrappedERC20 implementation used for token wrapping.
    address public immutable governanceWrappedERC20Base;

    /// @notice Token configuration identical to the vanilla TokenVoting setup.
    struct TokenSettings {
        address addr;
        string name;
        string symbol;
    }

    /// @notice Hats-specific configuration.
    struct HatsConfig {
        uint256 proposerHatId;
        uint256 voterHatId;
        uint256 executorHatId;
    }

    /// @notice Aggregated installation parameters, extending the vanilla setup with Hats configuration.
    struct InstallationParameters {
        MajorityVotingBase.VotingSettings votingSettings;
        TokenSettings tokenSettings;
        GovernanceERC20.MintSettings mintSettings;
        IPlugin.TargetConfig targetConfig;
        uint256 minApprovals;
        bytes pluginMetadata;
        address[] excludedAccounts;
        HatsConfig hatsConfig;
    }

    /// @notice Thrown if the provided token address is not a contract.
    error TokenNotContract(address token);

    /// @notice Thrown if the provided token address does not behave like an ERC20.
    error TokenNotERC20(address token);

    constructor(GovernanceERC20 _governanceERC20Base, GovernanceWrappedERC20 _governanceWrappedERC20Base)
        PluginUpgradeableSetup(address(new TokenVotingHats()))
    {
        tokenVotingHatsBase = TokenVotingHats(IMPLEMENTATION);
        governanceERC20Base = address(_governanceERC20Base);
        governanceWrappedERC20Base = address(_governanceWrappedERC20Base);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(address _dao, bytes calldata _data)
        external
        override
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        InstallationParameters memory params = decodeInstallationParametersHats(_data);
        TokenSettings memory tokenSettings = params.tokenSettings;
        HatsConfig memory hatsConfig = params.hatsConfig;
        address token = tokenSettings.addr;

        if (token != address(0)) {
            if (!token.isContract()) {
                revert TokenNotContract(token);
            }

            if (!_isERC20(token)) {
                revert TokenNotERC20(token);
            }

            if (!supportsIVotesInterface(token)) {
                token = governanceWrappedERC20Base.clone();
                GovernanceWrappedERC20(token).initialize(
                    IERC20Upgradeable(tokenSettings.addr), tokenSettings.name, tokenSettings.symbol
                );
            }
        } else {
            token = governanceERC20Base.clone();
            GovernanceERC20(token).initialize(IDAO(_dao), tokenSettings.name, tokenSettings.symbol, params.mintSettings);
        }

        plugin = address(tokenVotingHatsBase).deployUUPSProxy(
            abi.encodeCall(
                TokenVotingHats.initialize,
                (
                    IDAO(_dao),
                    params.votingSettings,
                    IVotesUpgradeable(token),
                    params.targetConfig,
                    params.minApprovals,
                    params.pluginMetadata,
                    params.excludedAccounts
                )
            )
        );

        address hatsCondition =
            address(new HatsCondition(hatsConfig.proposerHatId, hatsConfig.voterHatId, hatsConfig.executorHatId));

        preparedSetupData.helpers = new address[](2);
        preparedSetupData.helpers[0] = hatsCondition;
        preparedSetupData.helpers[1] = token;

        uint256 permissionEntries = tokenSettings.addr != address(0) ? 7 : 8;
        preparedSetupData.permissions = new PermissionLib.MultiTargetPermission[](permissionEntries);

        // Grant update voting settings permission to the DAO.
        preparedSetupData.permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingHatsBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });

        // Grant DAO execute permission to the plugin.
        preparedSetupData.permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        // Gate proposal creation by the proposer hat.
        preparedSetupData.permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: plugin,
            who: ANY_ADDR,
            condition: hatsCondition,
            permissionId: tokenVotingHatsBase.CREATE_PROPOSAL_PERMISSION_ID()
        });

        // Gate vote casting by the voter hat.
        preparedSetupData.permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: plugin,
            who: ANY_ADDR,
            condition: hatsCondition,
            permissionId: tokenVotingHatsBase.CAST_VOTE_PERMISSION_ID()
        });

        // Allow the DAO to manage target config.
        preparedSetupData.permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        // Allow the DAO to update metadata.
        preparedSetupData.permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        // Gate proposal execution by the executor hat.
        preparedSetupData.permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: plugin,
            who: ANY_ADDR,
            condition: hatsCondition,
            permissionId: tokenVotingHatsBase.EXECUTE_PROPOSAL_PERMISSION_ID()
        });

        if (tokenSettings.addr == address(0)) {
            bytes32 tokenMintPermission = GovernanceERC20(token).MINT_PERMISSION_ID();
            preparedSetupData.permissions[7] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: tokenMintPermission
            });
        }
    }

    /// @inheritdoc IPluginSetup
    function prepareUpdate(address _dao, uint16 _fromBuild, SetupPayload calldata _payload)
        external
        pure
        override
        returns (bytes memory, /* initData */ PreparedSetupData memory /* preparedSetupData */ )
    {
        (_dao, _fromBuild, _payload);
        revert InvalidUpdatePath({fromBuild: _fromBuild, thisBuild: THIS_BUILD});
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        override
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        permissions = new PermissionLib.MultiTargetPermission[](6);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingHatsBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingHatsBase.CREATE_PROPOSAL_PERMISSION_ID()
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingHatsBase.EXECUTE_PROPOSAL_PERMISSION_ID()
        });
    }

    /// @notice Encodes installation parameters including Hats configuration.
    function encodeInstallationParametersHats(
        MajorityVotingBase.VotingSettings memory votingSettings,
        TokenSettings memory tokenSettings,
        GovernanceERC20.MintSettings memory mintSettings,
        IPlugin.TargetConfig memory targetConfig,
        uint256 minApprovals,
        bytes memory pluginMetadata,
        address[] memory excludedAccounts,
        HatsConfig memory hatsConfig
    ) external pure returns (bytes memory) {
        InstallationParameters memory params = InstallationParameters({
            votingSettings: votingSettings,
            tokenSettings: tokenSettings,
            mintSettings: mintSettings,
            targetConfig: targetConfig,
            minApprovals: minApprovals,
            pluginMetadata: pluginMetadata,
            excludedAccounts: excludedAccounts,
            hatsConfig: hatsConfig
        });

        return abi.encode(params);
    }

    /// @notice Decodes installation parameters including Hats configuration.
    function decodeInstallationParametersHats(bytes memory _data)
        public
        pure
        returns (InstallationParameters memory params)
    {
        return abi.decode(_data, (InstallationParameters));
    }

    /// @notice Checks whether the provided token exposes the required IVotes interface.
    function supportsIVotesInterface(address token) public view returns (bool) {
        (bool success1, bytes memory data1) =
            token.staticcall(abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector, 0));
        (bool success2, bytes memory data2) =
            token.staticcall(abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, address(this)));
        (bool success3, bytes memory data3) =
            token.staticcall(abi.encodeWithSelector(IVotesUpgradeable.getPastVotes.selector, address(this), 0));

        return
            (success1 && data1.length == 0x20 && success2 && data2.length == 0x20 && success3 && data3.length == 0x20);
    }

    /// @notice Lightweight ERC20 interface check used during installation.
    function _isERC20(address token) private view returns (bool) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeCall(IERC20Upgradeable.balanceOf, (address(this))));
        return success && data.length == 0x20;
    }
}
