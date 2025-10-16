// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IDAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {TokenVotingSetupHats} from "../src/TokenVotingSetupHats.sol";
import {GovernanceERC20} from "../src/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "../src/erc20/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * This script performs the following tasks:
 * - Deploys a new PluginRepo
 * - Publishes the first version (release 1, build 1)
 *
 * The full plugin deployment should be made from the Protocol Factory.
 * This script is provided for separate ad-hoc deployments.
 */
contract DeployNewTokenVotingHatsRepoScript is Script {
    using stdJson for string;

    address deployer;
    string pluginEnsSubdomain;
    address pluginRepoMaintainerAddress;
    PluginRepoFactory pluginRepoFactory;
    GovernanceERC20 governanceERC20;
    GovernanceWrappedERC20 governanceWrappedERC20;
    bytes releaseMetadataUri;
    bytes buildMetadataUri;

    // Artifacts
    PluginRepo myPluginRepo;
    address pluginSetup;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);

        deployer = vm.addr(privKey);
        console2.log("General");
        console2.log("- Deploying from:   ", deployer);
        console2.log("- Chain ID:         ", block.chainid);
        console2.log("");

        _;

        vm.stopBroadcast();
    }

    function setUp() public {
        // Pick the contract addresses from
        // https://github.com/aragon/osx/blob/main/packages/artifacts/src/addresses.json

        // Prepare the OSx factories for the current network
        pluginRepoFactory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS"));
        vm.label(address(pluginRepoFactory), "PluginRepoFactory");

        // Set the governance ERC20 and wrapped ERC20 addresses
        governanceERC20 = GovernanceERC20(vm.envAddress("GOVERNANCE_ERC20_ADDRESS"));
        governanceWrappedERC20 = GovernanceWrappedERC20(vm.envAddress("GOVERNANCE_WRAPPED_ERC20_ADDRESS"));
        vm.label(address(governanceERC20), "GovernanceERC20");
        vm.label(address(governanceWrappedERC20), "GovernanceWrappedERC20");

        // Read the rest of environment variables
        pluginEnsSubdomain = vm.envOr("PLUGIN_ENS_SUBDOMAIN", string(""));

        // Using a random subdomain if empty
        if (bytes(pluginEnsSubdomain).length == 0) {
            pluginEnsSubdomain = string.concat("my-token-voting-plugin-", vm.toString(block.timestamp));
        }

        pluginRepoMaintainerAddress = vm.envAddress("PLUGIN_REPO_MAINTAINER_ADDRESS");
        vm.label(pluginRepoMaintainerAddress, "Maintainer");

        releaseMetadataUri = vm.envOr("RELEASE_METADATA_URI", bytes(" "));
        buildMetadataUri = vm.envOr("BUILD_METADATA_URI", bytes(" "));
    }

    function run() public broadcast {
        // Publish the first version in a new plugin repo
        deployPluginRepo();

        // Done
        printDeployment();

        // Write the addresses to a JSON file
        if (!vm.envOr("SIMULATION", false)) {
            writeJsonArtifacts();
        }
    }

    function deployPluginRepo() public {
        // Plugin setup (the installer)
        pluginSetup = address(new TokenVotingSetupHats(governanceERC20, governanceWrappedERC20));

        // The new plugin repository
        // Publish the plugin in a new repo as release 1, build 1
        myPluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            pluginEnsSubdomain, pluginSetup, pluginRepoMaintainerAddress, releaseMetadataUri, buildMetadataUri
        );
    }

    function printDeployment() public view {
        console2.log("TokenVotingHats plugin:");
        console2.log("- Plugin repo:               ", address(myPluginRepo));
        console2.log("- Plugin repo maintainer:    ", pluginRepoMaintainerAddress);
        console2.log("- ENS:                       ", string.concat(pluginEnsSubdomain, ".plugin.dao.eth"));
        console2.log("- GovernanceERC20:           ", address(governanceERC20));
        console2.log("- GovernanceWrappedERC20:    ", address(governanceWrappedERC20));
        console2.log("");
    }

    function writeJsonArtifacts() internal {
        string memory artifacts = "output";
        artifacts.serialize("pluginRepo", address(myPluginRepo));
        artifacts.serialize("pluginSetup", address(pluginSetup));
        artifacts.serialize("governanceERC20", address(governanceERC20));
        artifacts.serialize("governanceWrappedERC20", address(governanceWrappedERC20));
        artifacts.serialize("pluginRepoMaintainer", pluginRepoMaintainerAddress);
        artifacts = artifacts.serialize("pluginEnsDomain", string.concat(pluginEnsSubdomain, ".plugin.dao.eth"));

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory filePath = string.concat(
            vm.projectRoot(), "/artifacts/deployment-", networkName, "-", vm.toString(block.timestamp), ".json"
        );
        artifacts.write(filePath);

        console2.log("Deployment artifacts written to", filePath);
    }
}
