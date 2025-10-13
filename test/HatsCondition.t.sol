// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {HatsCondition} from "../src/condition/HatsCondition.sol";
import {IHats} from "../src/interfaces/IHats.sol";

contract HatsConditionTest is Test {
    bytes32 internal constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");
    bytes32 internal constant CAST_VOTE_PERMISSION_ID = keccak256("CAST_VOTE_PERMISSION");
    bytes32 internal constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

    address internal constant HATS_PROTOCOL = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    HatsCondition internal condition;

    function setUp() public {
        condition = new HatsCondition(111, 222, 333);
    }

    function _mockHatWearer(address wearer, uint256 hatId, bool value) internal {
        vm.mockCall(
            HATS_PROTOCOL,
            abi.encodeWithSelector(IHats.isWearerOfHat.selector, wearer, hatId),
            abi.encode(value)
        );
    }

    function test_WhenWearerHasMappedHat_ThenPermissionGranted() external {
        address wearer = address(0xA11CE);
        _mockHatWearer(wearer, 111, true);
        _mockHatWearer(wearer, 222, true);
        _mockHatWearer(wearer, 333, true);

        assertTrue(condition.isGranted(address(0), wearer, CREATE_PROPOSAL_PERMISSION_ID, ""), "proposer hat");
        assertTrue(condition.isGranted(address(0), wearer, CAST_VOTE_PERMISSION_ID, ""), "voter hat");
        assertTrue(condition.isGranted(address(0), wearer, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "executor hat");
    }

    function test_WhenWearerLacksHat_ThenPermissionDenied() external {
        address wearer = address(0xB0B);
        _mockHatWearer(wearer, 111, false);
        _mockHatWearer(wearer, 222, false);
        _mockHatWearer(wearer, 333, false);

        assertFalse(condition.isGranted(address(0), wearer, CREATE_PROPOSAL_PERMISSION_ID, ""), "proposer denied");
        assertFalse(condition.isGranted(address(0), wearer, CAST_VOTE_PERMISSION_ID, ""), "voter denied");
        assertFalse(condition.isGranted(address(0), wearer, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "executor denied");
    }

    function test_WhenPermissionUsesSentinel_ThenBypassGranted() external {
        HatsCondition sentinelCondition = new HatsCondition(1, 1, 1);
        address wearer = address(0xC0DE);

        // All permissions bypassed because sentinel used for each mapping.
        assertTrue(sentinelCondition.isGranted(address(0), wearer, CREATE_PROPOSAL_PERMISSION_ID, ""), "create sentinel");
        assertTrue(sentinelCondition.isGranted(address(0), wearer, CAST_VOTE_PERMISSION_ID, ""), "vote sentinel");
        assertTrue(sentinelCondition.isGranted(address(0), wearer, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "execute sentinel");
    }

    function test_WhenPermissionNotConfigured_ThenDenied() external view {
        address wearer = address(0xD0D0);
        bool granted = condition.isGranted(address(0), wearer, bytes32("UNKNOWN_PERMISSION"), "");
        assertFalse(granted, "unknown permission should default to deny");
    }

    function test_WhenHatIdZero_ThenAlwaysDenied() external {
        HatsCondition zeroHatCondition = new HatsCondition(0, 0, 0);
        address wearer = address(0xCAFE);

        _mockHatWearer(wearer, 0, true);
        bool granted = zeroHatCondition.isGranted(address(0), wearer, CREATE_PROPOSAL_PERMISSION_ID, "");
        assertFalse(granted, "zero hat id must deny even if mocked true");
    }
}
