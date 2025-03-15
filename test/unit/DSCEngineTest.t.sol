// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/Console.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockDscMintFailed} from "test/mocks/MockDscMintFailed.sol";
import {MockTransferFailed} from "test/mocks/MockTransferFailed.sol";
import {MockTransferFromFailed} from "test/mocks/MockTransferFromFailed.sol";
import {MockBurnFailed} from "test/mocks/MockBurnFailed.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant DSC_MINTED = 1;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(user2, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier approveBurn() {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), DSC_MINTED);
        vm.stopPrank();
        _;
    }

    /* ------------- CONSTRUCTOR TESTS ------------- */
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /* ------------- PRICE FEED TESTS ------------- */
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2,000 / ETH, $100 = 0.05
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 accountCollateralValue = dscEngine.getAccountCollateralValue(user);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(accountCollateralValue, expectedCollateralValue);
    }

    function testGetAccountInformation() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDSC(DSC_MINTED);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 expectedMintedDsc = DSC_MINTED;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        vm.stopPrank();
        assertEq(totalDscMinted, expectedMintedDsc);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /* ------------- DEPOSIT COLLATERAL TESTS ------------- */
    function testRevertsIfDepositCollateralFailed() public {
        // Arrange
        MockTransferFromFailed mockDsc = new MockTransferFromFailed();
        tokenAddresses.push(address(mockDsc));
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(user, 100 ether);
        mockDsc.transferOwnership(address(mockDscEngine));
        // Assert - Act
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user, STARTING_ERC20_BALANCE);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(randomToken), 1 ether);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        uint256 expectedMintedDsc = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedMintedDsc);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_MINTED);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 expectedCollateralValueInUsd = dscEngine.getAccountCollateralValue(user);

        assertEq(DSC_MINTED, totalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
    }

    /* ------------- MINTING TESTS ------------- */
    function testMintingRevertsIfMintingZero() public depositedCollateral {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDSC(0);
        vm.stopPrank();
    }

    function testMinting() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDSC(DSC_MINTED);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);

        assertEq(DSC_MINTED, totalDscMinted);
    }

    function testMintingFails() public depositedCollateral {
        // Arrange
        MockDscMintFailed mockDsc = new MockDscMintFailed();
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDscEngine));
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_MINTED);
        vm.stopPrank();
    }

    /* ------------- BURN TESTS ------------- */
    function testBurnRevertsIfBurningZero() public approveBurn {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testBurnFails() public {
        // Arrange
        MockBurnFailed mockDsc = new MockBurnFailed();
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDscEngine));
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        // Act / Assert
        mockDscEngine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_MINTED);
        mockDsc.approve(address(mockDscEngine), DSC_MINTED);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.burnDSC(1);
        vm.stopPrank();
    }

    function testDscBurn() public depositedCollateral {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), DSC_MINTED);
        dscEngine.mintDSC(10);
        dscEngine.burnDSC(DSC_MINTED);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);

        assertEq(9, totalDscMinted);
    }

    /* ------------- REDEEM COLLATERAL TESTS ------------- */
    function testRedeemCollateralRevertsIfRedeemingZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralTransferFailed() public {
        // Arrange
        MockTransferFailed mockDsc = new MockTransferFailed();
        tokenAddresses.push(address(mockDsc));
        priceFeedAddresses.push(ethUsdPriceFeed);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));

        mockDsc.mint(user, 100 ether);
        mockDsc.transferOwnership(address(mockDscEngine));

        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        // Act / Assert
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralWorks() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDSC(1 ether);
        uint256 collateralValueInUsd = dscEngine.getAccountCollateralValue(user);
        // 2000e18 * 10 =
        // 20000,000000000000000000
        dscEngine.redeemCollateral(weth, 5 ether);
        uint256 expectedNewCollateralValue = collateralValueInUsd - dscEngine.getUsdValue(weth, 5 ether);
        uint256 newCollateralValueInUsd = dscEngine.getAccountCollateralValue(user);
        vm.stopPrank();

        assertEq(expectedNewCollateralValue, newCollateralValueInUsd);
    }

    function testRedeemCollateralForDSC() public depositedCollateral {
        vm.startPrank(user);
        uint256 depositedCollateralValueInusd = dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDSC(100);
        dsc.approve(address(dscEngine), 100);
        dscEngine.redeemCollateralForDSC(weth, 0.5 ether, 5);
        uint256 redeemCollateralValueInUsd = dscEngine.getUsdValue(weth, 0.5 ether);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        assertEq(95, totalDscMinted);
        assertEq(depositedCollateralValueInusd - redeemCollateralValueInUsd, collateralValueInUsd);
    }

    /* ------------- HEALTH FACTOR TESTS ------------- */
    function testRevertsIfHealthFactorIsBrokenAfterMintingTooMuch() public depositedCollateral {
        uint256 healthFactor = 1000;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, healthFactor));
        dscEngine.mintDSC(10e36);
        vm.stopPrank();
    }

    function testGetHealthFactor() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDSC(1 ether);
        uint256 actualHealthFactor = dscEngine.getHealthFactor(user);
        // this should return:
        // precision: 1e18, liquidationthreshold = 50, liquidationprecision = 100

        // depostied eth 10 = 10e18
        // total DSC minted = 1e18
        // 10e18 * 2000 = 20000e18
        // collateralvalueinusd for 10e18 weth at 2k ETH price = 20000e18
        // colladjustedforthreshold = (collvalinusd *liquidthreshold) / liquidpreicision
        // (20000e18 * 50) / 100 = 10000e18
        // colladjustedforthreshold * precision / totaldsc
        // 10000e18 * 1e18 / 1e18 = 10000e18 <- health factor
        uint256 expectedHealthFactor = 10000e18;
        assertEq(actualHealthFactor, expectedHealthFactor);
        vm.stopPrank();
    }

    /* ------------- LIQUIDATION TESTS ------------- */
    function testLiquidationRevertsIfLiquidatingZero() public depositedCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.liquidate(weth, user, 0);
        vm.stopPrank();
    }

    function testLiquidationRevertsIfHealthFactorOK() public depositedCollateral {
        // Arrange
        vm.startPrank(user);
        dscEngine.mintDSC(1);
        vm.stopPrank();

        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDSC(1);

        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        dscEngine.liquidate(weth, user, 1);
        vm.stopPrank();
    }

    function testLiquidationWorks() public {
        // Arrange
        // set up user - who will be liquidator
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDSC(5 ether); // mint only a small amount of DSC
        vm.stopPrank();

        // set up user2 - who will be liquidated
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDSC(100 ether); // minting a lot more dsc than user 1
        vm.stopPrank();

        // Price of ETH prices user2 below health factor and is liquidatable
        int256 loweredEthPrice = 15e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(loweredEthPrice);

        // Act - Assert
        vm.startPrank(user);
        dsc.approve(address(dscEngine), 200 ether);
        dscEngine.liquidate(weth, user2, 5 ether);
        vm.stopPrank();

        uint256 userMintedDsc = dscEngine.getDscMintedByUser(user);
        uint256 user2MintedDsc = dscEngine.getDscMintedByUser(user2);
        assertEq(userMintedDsc, 5 ether);
        assertEq(user2MintedDsc, 95 ether);
    }

    function testLiquidationDoesntImproveHealthFactor() public {
        // Arrange
        // set up user - who will be liquidator
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDSC(5 ether); // mint only a small amount of DSC
        vm.stopPrank();

        // set up user2 - who will be liquidated
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        dscEngine.mintDSC(100 ether); // minting a lot more dsc than user 1
        vm.stopPrank();

        // Price of ETH prices user2 below health factor and is liquidatable
        int256 loweredEthPrice = 15e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(loweredEthPrice);

        // Act - Assert
        vm.startPrank(user);
        dsc.approve(address(dscEngine), 200 ether);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        dscEngine.liquidate(weth, user2, 1);
        vm.stopPrank();
    }
}
