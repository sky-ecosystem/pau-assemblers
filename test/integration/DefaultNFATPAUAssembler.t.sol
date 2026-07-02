// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IDefaultNFATPAUAssembler } from "../../src/interfaces/IDefaultNFATPAUAssembler.sol";
import { IPAUAssembler }            from "../../src/interfaces/IPAUAssembler.sol";

import { DefaultNFATPAUAssembler, INFATFacilityFactoryLike } from "../../src/DefaultNFATPAUAssembler.sol";
import { PAUAssembler }                                      from "../../src/PAUAssembler.sol";

interface IAccessControlLike {

    function hasRole(bytes32 role, address account) external view returns (bool);

}

contract DefaultNFATPAUAssembler_Integration_Tests is Test {

    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant ACCESS_CONTROLS_ID = "ACCESS_CONTROLS";
    bytes32 internal constant RATE_LIMITS_ID     = "RATE_LIMITS";

    address internal constant NFAT_FACILITY = address(0xFAC111);

    PAUAssembler            internal pauAssembler;
    address                 internal nfatFacilityFactory;
    DefaultNFATPAUAssembler internal assembler;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        // The NFATFacilityFactory is not deployed on mainnet, so the real PAUAssembler runs against
        // the forked PAUFactory while the NFAT factory is mocked here.
        nfatFacilityFactory = makeAddr("nfatFacilityFactory");

        vm.mockCall(
            nfatFacilityFactory,
            abi.encodeWithSelector(INFATFacilityFactoryLike.deploy.selector),
            abi.encode(NFAT_FACILITY)
        );

        pauAssembler = new PAUAssembler(ADMINISTERED_AGENT_FACTORY, PAU_FACTORY);
        assembler    = new DefaultNFATPAUAssembler(nfatFacilityFactory, address(pauAssembler));
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroNFATFacilityFactory() external {
        vm.expectRevert(IDefaultNFATPAUAssembler.ZeroNFATFacilityFactory.selector);
        new DefaultNFATPAUAssembler(address(0), address(pauAssembler));
    }

    function test_constructor_zeroPAUAssembler() external {
        vm.expectRevert(IDefaultNFATPAUAssembler.ZeroPAUAssembler.selector);
        new DefaultNFATPAUAssembler(nfatFacilityFactory, address(0));
    }

    /**********************************************************************************************/
    /*** Initial State Test                                                                     ***/
    /**********************************************************************************************/

    function test_initialState() external view {
        assertEq(assembler.VERSION(),              "1.0.0");
        assertEq(assembler.nfatFacilityFactory(),  nfatFacilityFactory);
        assertEq(assembler.pauAssembler(),         address(pauAssembler));
    }

    /**********************************************************************************************/
    /*** deploy Tests                                                                           ***/
    /**********************************************************************************************/

    function _pauInput() internal returns (IDefaultNFATPAUAssembler.PAUAssemblerConfigs memory input) {
        IPAUAssembler.AccessControlsConfig[] memory accessControlsConfigs = new IPAUAssembler.AccessControlsConfig[](1);
        accessControlsConfigs[0].id        = ACCESS_CONTROLS_ID;
        accessControlsConfigs[0].admins    = new address[](1);
        accessControlsConfigs[0].admins[0] = makeAddr("acAdmin");

        IPAUAssembler.RateLimitsConfig[] memory rateLimitsConfigs = new IPAUAssembler.RateLimitsConfig[](1);
        rateLimitsConfigs[0].id        = RATE_LIMITS_ID;
        rateLimitsConfigs[0].admins    = new address[](1);
        rateLimitsConfigs[0].admins[0] = makeAddr("rlAdmin");

        IPAUAssembler.ControllerConfig[] memory controllerConfigs = new IPAUAssembler.ControllerConfig[](1);
        controllerConfigs[0].rateLimitsId     = RATE_LIMITS_ID;
        controllerConfigs[0].accessControlsId = ACCESS_CONTROLS_ID;

        IPAUAssembler.AdministeredAgentConfig[] memory agentConfigs = new IPAUAssembler.AdministeredAgentConfig[](1);
        agentConfigs[0].accessControlsId = ACCESS_CONTROLS_ID;
        agentConfigs[0].admins           = new address[](1);
        agentConfigs[0].admins[0]        = makeAddr("agentAdmin");

        IPAUAssembler.ALMProxyConfig memory proxyConfig;
        proxyConfig.admins    = new address[](1);
        proxyConfig.admins[0] = makeAddr("proxyAdmin");

        input.controllerConfigs     = controllerConfigs;
        input.rateLimitsConfigs     = rateLimitsConfigs;
        input.accessControlsConfigs = accessControlsConfigs;
        input.allocatorAgentConfigs = agentConfigs;
        input.almProxyConfig        = proxyConfig;
    }

    function _nfatFacilityFactoryInput() internal returns (IDefaultNFATPAUAssembler.NFATFacilityFactoryConfig memory input) {
        input.name            = "NFAT";
        input.symbol          = "NFT";
        input.baseURI         = "ipfs://base/";
        input.gem             = makeAddr("gem");
        input.identityNetwork = makeAddr("identityNetwork");

        input.wards    = new address[](1);
        input.wards[0] = makeAddr("ward");

        input.cops    = new address[](1);
        input.cops[0] = makeAddr("cop");
    }

    function test_deploy() external {
        IDefaultNFATPAUAssembler.PAUAssemblerConfigs       memory pauInput                 = _pauInput();
        IDefaultNFATPAUAssembler.NFATFacilityFactoryConfig memory nfatFacilityFactoryInput = _nfatFacilityFactoryInput();

        // PAUAssembler deploys the shared ALMProxy first, so its address is the PAUFactory's next CREATE.
        address expectedProxy = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY));

        address[] memory expectedBuds = new address[](1);
        expectedBuds[0] = expectedProxy;

        // The NFAT factory must be called with recipient == sole bud == the shared ALMProxy, and all
        // pass-through fields forwarded verbatim.
        vm.expectCall(
            nfatFacilityFactory,
            abi.encodeCall(
                INFATFacilityFactoryLike.deploy,
                (
                    nfatFacilityFactoryInput.name,
                    nfatFacilityFactoryInput.symbol,
                    nfatFacilityFactoryInput.baseURI,
                    nfatFacilityFactoryInput.gem,
                    expectedProxy,
                    nfatFacilityFactoryInput.identityNetwork,
                    nfatFacilityFactoryInput.wards,
                    expectedBuds,
                    nfatFacilityFactoryInput.cops
                )
            )
        );

        (
            address          proxy,
            address          nfatFacility,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        ) = assembler.deploy(pauInput, nfatFacilityFactoryInput);

        assertEq(proxy, expectedProxy);

        // --- Facility address is what the factory returned.
        assertEq(nfatFacility, NFAT_FACILITY);

        // --- PAU stack came back intact.
        assertEq(controllers.length,     1);
        assertEq(accessControls.length,  1);
        assertEq(rateLimits.length,      1);
        assertEq(allocatorAgents.length, 1);

        // The assembler must hold no roles on the shared proxy after deploy.
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, address(pauAssembler)),  false);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),     false);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("proxyAdmin")), true);
    }

    function test_deploy_emitsDeployment() external {
        IDefaultNFATPAUAssembler.PAUAssemblerConfigs       memory pauInput                 = _pauInput();
        IDefaultNFATPAUAssembler.NFATFacilityFactoryConfig memory nfatFacilityFactoryInput = _nfatFacilityFactoryInput();

        // PAUAssembler deploys in CREATE order: proxy, accessControls, rateLimits, controller.
        address[] memory expectedControllers = new address[](1);
        expectedControllers[0] = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY) + 3);

        address[] memory expectedAccessControls = new address[](1);
        expectedAccessControls[0] = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY) + 1);

        address[] memory expectedRateLimits = new address[](1);
        expectedRateLimits[0] = vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY) + 2);

        address[] memory expectedAllocatorAgents = new address[](1);
        expectedAllocatorAgents[0] = vm.computeCreateAddress(ADMINISTERED_AGENT_FACTORY, vm.getNonce(ADMINISTERED_AGENT_FACTORY));

        vm.expectEmit(address(assembler));
        emit IDefaultNFATPAUAssembler.Deployment(
            vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY)),
            NFAT_FACILITY,
            expectedControllers,
            expectedAccessControls,
            expectedRateLimits,
            expectedAllocatorAgents,
            pauInput,
            nfatFacilityFactoryInput
        );

        assembler.deploy(pauInput, nfatFacilityFactoryInput);
    }

}
