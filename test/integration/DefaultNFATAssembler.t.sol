// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IDefaultNFATAssembler } from "../../src/interfaces/IDefaultNFATAssembler.sol";
import { IPAUAssembler }         from "../../src/interfaces/IPAUAssembler.sol";

import { DefaultNFATAssembler } from "../../src/DefaultNFATAssembler.sol";
import { PAUAssembler }         from "../../src/PAUAssembler.sol";

interface IAccessControlLike {

    function hasRole(bytes32 role, address account) external view returns (bool);

}

interface IALMProxyLike {

    function CONTROLLER() external view returns (bytes32);

}

/**
 * @notice Records the exact arguments the {DefaultNFATAssembler} forwards to the NFAT factory, so
 *         the recipient/bud wiring (both must be the shared ALMProxy) can be asserted. The
 *         NFATFacilityFactory is not deployed on mainnet, so the real PAUAssembler runs against the
 *         forked PAUFactory while the NFAT factory is mocked here.
 */
contract MockNFATFactory {

    string    public name;
    string    public symbol;
    string    public baseURI;
    address   public gem;
    address   public recipient;
    address   public identityNetwork;
    address[] public wards;
    address[] public buds;
    address[] public cops;

    address public facility = address(0xFAC111);

    function deploy(
        string    memory name_,
        string    memory symbol_,
        string    memory baseURI_,
        address          gem_,
        address          recipient_,
        address          identityNetwork_,
        address[] memory wards_,
        address[] memory buds_,
        address[] memory cops_
    ) external returns (address) {
        name            = name_;
        symbol          = symbol_;
        baseURI         = baseURI_;
        gem             = gem_;
        recipient       = recipient_;
        identityNetwork = identityNetwork_;
        wards           = wards_;
        buds            = buds_;
        cops            = cops_;

        return facility;
    }

    function budsLength() external view returns (uint256) {
        return buds.length;
    }

    function wardsLength() external view returns (uint256) {
        return wards.length;
    }

}

contract DefaultNFATAssembler_Integration_Tests is Test {

    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 internal constant AC_A = "AC_A";
    bytes32 internal constant RL_A = "RL_A";

    PAUAssembler         internal pauAssembler;
    MockNFATFactory      internal nfatFactory;
    DefaultNFATAssembler internal assembler;

    function setUp() external {
        vm.createSelectFork("mainnet", 25270600);

        pauAssembler = new PAUAssembler(ADMINISTERED_AGENT_FACTORY, PAU_FACTORY);
        nfatFactory  = new MockNFATFactory();
        assembler    = new DefaultNFATAssembler(address(nfatFactory), address(pauAssembler));
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroNFATFactory() external {
        vm.expectRevert(IDefaultNFATAssembler.ZeroNFATFactory.selector);
        new DefaultNFATAssembler(address(0), address(pauAssembler));
    }

    function test_constructor_zeroPAUAssembler() external {
        vm.expectRevert(IDefaultNFATAssembler.ZeroPAUAssembler.selector);
        new DefaultNFATAssembler(address(nfatFactory), address(0));
    }

    /**********************************************************************************************/
    /*** Initial State Test                                                                     ***/
    /**********************************************************************************************/

    function test_initialState() external view {
        assertEq(assembler.VERSION(),      "1.0.0");
        assertEq(assembler.nfatFactory(),  address(nfatFactory));
        assertEq(assembler.pauAssembler(), address(pauAssembler));
    }

    /**********************************************************************************************/
    /*** deploy Tests                                                                           ***/
    /**********************************************************************************************/

    function _pauInput() internal returns (IDefaultNFATAssembler.PAUAssemblerInput memory input) {
        IPAUAssembler.AccessControlConfig[] memory acs = new IPAUAssembler.AccessControlConfig[](1);
        acs[0].id        = AC_A;
        acs[0].admins    = new address[](1);
        acs[0].admins[0] = makeAddr("acAdmin");

        IPAUAssembler.RateLimitConfig[] memory rls = new IPAUAssembler.RateLimitConfig[](1);
        rls[0].id        = RL_A;
        rls[0].admins    = new address[](1);
        rls[0].admins[0] = makeAddr("rlAdmin");

        IPAUAssembler.ControllerConfig[] memory ctrls = new IPAUAssembler.ControllerConfig[](1);
        ctrls[0].rateLimitId     = RL_A;
        ctrls[0].accessControlId = AC_A;

        IPAUAssembler.AdministeredAgentConfig[] memory agents = new IPAUAssembler.AdministeredAgentConfig[](1);
        agents[0].accessControlId = AC_A;
        agents[0].admins          = new address[](1);
        agents[0].admins[0]       = makeAddr("agentAdmin");

        IPAUAssembler.ALMProxyConfig memory proxyConfig;
        proxyConfig.admins    = new address[](1);
        proxyConfig.admins[0] = makeAddr("proxyAdmin");

        input.controllerConfigs     = ctrls;
        input.rateLimitConfigs      = rls;
        input.accessControlConfigs  = acs;
        input.allocatorAgentConfigs = agents;
        input.almProxyConfig        = proxyConfig;
    }

    function _nfatInput() internal returns (IDefaultNFATAssembler.NFATFactoryInput memory input) {
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
        IDefaultNFATAssembler.PAUAssemblerInput memory pauInput  = _pauInput();
        IDefaultNFATAssembler.NFATFactoryInput  memory nfatInput = _nfatInput();

        (
            address          proxy,
            address          nfatFacility,
            address[] memory controllers,
            address[] memory accessControls,
            address[] memory rateLimits,
            address[] memory allocatorAgents
        ) = assembler.deploy(pauInput, nfatInput);

        // --- Facility address is what the factory returned.
        assertEq(nfatFacility, nfatFactory.facility());

        // --- PAU stack came back intact.
        assertEq(controllers.length,     1);
        assertEq(accessControls.length,  1);
        assertEq(rateLimits.length,      1);
        assertEq(allocatorAgents.length, 1);

        // The assembler must hold no roles on the shared proxy after deploy.
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, address(pauAssembler)), false);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, address(assembler)),    false);
        assertEq(IAccessControlLike(proxy).hasRole(DEFAULT_ADMIN_ROLE, makeAddr("proxyAdmin")), true);

        // --- The NFAT factory was called with recipient == bud == the shared ALMProxy.
        assertEq(nfatFactory.recipient(),  proxy);
        assertEq(nfatFactory.budsLength(), 1);
        assertEq(nfatFactory.buds(0),      proxy);

        // --- Pass-through fields forwarded verbatim.
        assertEq(nfatFactory.name(),            "NFAT");
        assertEq(nfatFactory.symbol(),          "NFT");
        assertEq(nfatFactory.baseURI(),         "ipfs://base/");
        assertEq(nfatFactory.gem(),             makeAddr("gem"));
        assertEq(nfatFactory.identityNetwork(), makeAddr("identityNetwork"));
        assertEq(nfatFactory.wardsLength(),     1);
        assertEq(nfatFactory.wards(0),          makeAddr("ward"));
        assertEq(nfatFactory.cops(0),           makeAddr("cop"));
    }

    function test_deploy_emitsDeployment() external {
        IDefaultNFATAssembler.PAUAssemblerInput memory pauInput  = _pauInput();
        IDefaultNFATAssembler.NFATFactoryInput  memory nfatInput = _nfatInput();

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
        emit IDefaultNFATAssembler.Deployment(
            vm.computeCreateAddress(PAU_FACTORY, vm.getNonce(PAU_FACTORY)),
            nfatFactory.facility(),
            expectedControllers,
            expectedAccessControls,
            expectedRateLimits,
            expectedAllocatorAgents,
            pauInput,
            nfatInput
        );

        assembler.deploy(pauInput, nfatInput);
    }

}
