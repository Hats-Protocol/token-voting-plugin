// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IDAO} from "@aragon/osx/core/dao/DAO.sol";
import {TokenVotingSetupHats} from "../src/TokenVotingSetupHats.sol";
import {GovernanceERC20} from "../src/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "../src/erc20/GovernanceWrappedERC20.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @notice Deploys the Hats-enabled TokenVoting setup contract alongside its ERC20 helper bases.
contract DeployTokenVotingHatsScript is Script {
    using stdJson for string;

    address deployer;
    PluginRepo pluginRepo;

    address pluginSetup;
    GovernanceERC20 governanceERC20;
    GovernanceWrappedERC20 governanceWrappedERC20;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);

        deployer = vm.addr(privKey);
        console2.log("Hats TokenVoting Deployment");
        console2.log("- Deployer:          ", deployer);
        console2.log("- Chain ID:          ", block.chainid);
        console2.log("");

        _;

        vm.stopBroadcast();
    }

    function setUp() public {
        pluginRepo = PluginRepo(vm.envAddress("PLUGIN_REPO_ADDRESS"));
        vm.label(address(pluginRepo), "PluginRepo");
    }

    function run() public broadcast {
        deployPluginSetup();
        printDeployment();

        if (!vm.envOr("SIMULATION", false)) {
            writeJsonArtifacts();
        }
    }

    function deployPluginSetup() public {
        governanceERC20 = new GovernanceERC20(
            IDAO(address(0)), "", "", GovernanceERC20.MintSettings(new address[](0), new uint256[](0), false)
        );
        governanceWrappedERC20 = new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "");

        pluginSetup = address(new TokenVotingSetupHats(governanceERC20, governanceWrappedERC20));
    }

    function printDeployment() public view {
        console2.log("TokenVotingHats setup components:");
        console2.log("- PluginSetup:               ", address(pluginSetup));
        console2.log("- GovernanceERC20:           ", address(governanceERC20));
        console2.log("- GovernanceWrappedERC20:    ", address(governanceWrappedERC20));
        console2.log("- PluginRepo:                ", address(pluginRepo));
        console2.log("");
    }

    function writeJsonArtifacts() internal {
        string memory artifacts = "output";
        artifacts.serialize("pluginRepo", address(pluginRepo));
        artifacts.serialize("pluginSetup", address(pluginSetup));
        artifacts.serialize("governanceERC20", address(governanceERC20));
        artifacts = artifacts.serialize("governanceWrappedERC20", address(governanceWrappedERC20));

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory filePath = string.concat(
            vm.projectRoot(), "/artifacts/hats-deployment-", networkName, "-", vm.toString(block.timestamp), ".json"
        );
        artifacts.write(filePath);

        console2.log("Deployment artifacts written to", filePath);
    }
}
