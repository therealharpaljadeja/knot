// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Executor } from "../src/Executor.sol";
import { FlashLoanHandler } from "../src/FlashLoanHandler.sol";
import { HandlerBase } from "../src/HandlerBase.sol";
import { HandlerFunds } from "../src/HandlerFunds.sol";
import { Registry } from "../src/Registry.sol";
import { IFlashLoanSimpleReceiver } from "../src/interfaces/IMoncombo.sol";

contract ThreeActionAssessmentTest is Test {
    uint256 internal constant BORROW_AMOUNT = 1_000_000;
    uint256 internal constant PREMIUM = 500;

    address internal user = makeAddr("user");
    address internal spenderA = makeAddr("spender-a");
    address internal spenderB = makeAddr("spender-b");
    address internal spenderC = makeAddr("spender-c");

    Registry internal registry;
    Executor internal executor;
    FlashLoanHandler internal flashLoanHandler;
    HandlerFunds internal fundsHandler;
    AssessmentHandler internal assessmentHandler;
    OrderRecorder internal recorder;
    MockERC20 internal usdc;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    MockERC20 internal tokenD;
    address internal pool;

    function setUp() public {
        registry = new Registry(address(this));
        executor = new Executor(address(registry), address(this));
        flashLoanHandler = new FlashLoanHandler(address(registry));
        fundsHandler = new HandlerFunds();
        assessmentHandler = new AssessmentHandler();
        recorder = new OrderRecorder();
        usdc = new MockERC20("Mock USDC", "mUSDC");
        tokenB = new MockERC20("Token B", "TKB");
        tokenC = new MockERC20("Token C", "TKC");
        tokenD = new MockERC20("Token D", "TKD");

        registry.setHandler(address(flashLoanHandler), true);
        registry.setHandler(address(fundsHandler), true);
        registry.setHandler(address(assessmentHandler), true);

        pool = address(flashLoanHandler.POOL());
        MockPool poolImplementation = new MockPool();
        vm.etch(pool, address(poolImplementation).code);
        registry.setCaller(pool, address(flashLoanHandler));
    }

    function testThreeActionsCleanBalancesAndApprovals() public {
        address[] memory tokens = _repeat(address(tokenB));
        address[] memory spenders = _repeat(spenderA);

        _executeTouches(tokens, spenders, address(recorder));

        assertEq(recorder.length(), 3);
        assertEq(recorder.at(0), 1);
        assertEq(recorder.at(1), 2);
        assertEq(recorder.at(2), 3);
        assertEq(usdc.balanceOf(address(executor)), 0);
        assertEq(tokenB.balanceOf(address(executor)), 0);
        assertEq(tokenB.balanceOf(user), 3);
        assertEq(usdc.allowance(address(executor), pool), 0);
        assertEq(tokenB.allowance(address(executor), spenderA), 0);
        assertEq(usdc.allowance(user, address(executor)), 0);
    }

    function testBookkeepingKeysCanBeReusedInASecondCombo() public {
        address[] memory tokens = _repeat(address(tokenB));
        address[] memory spenders = _repeat(spenderA);

        _executeTouches(tokens, spenders, address(0));
        _executeTouches(tokens, spenders, address(0));

        assertEq(tokenB.balanceOf(user), 6);
        assertEq(tokenB.balanceOf(address(executor)), 0);
        assertEq(tokenB.allowance(address(executor), spenderA), 0);
        assertEq(usdc.allowance(address(executor), pool), 0);
    }

    function testFirstActionFailureRevertsAtomically() public {
        _assertAtomicFailure(0);
    }

    function testSecondActionFailureRevertsAtomically() public {
        _assertAtomicFailure(1);
    }

    function testThirdActionFailureRevertsAtomically() public {
        _assertAtomicFailure(2);
    }

    function testGasTwoActionsWithRepeatedBookkeepingKeys() public {
        uint256 gasUsed = _measureTouches(2, _repeat(address(tokenB)), _repeat(spenderA));
        emit log_named_uint("two actions, repeated keys", gasUsed);
    }

    function testGasThreeActionsWithRepeatedBookkeepingKeys() public {
        uint256 gasUsed = _measureTouches(3, _repeat(address(tokenB)), _repeat(spenderA));
        emit log_named_uint("three actions, repeated keys", gasUsed);
    }

    function testGasThreeActionsWithDistinctApprovals() public {
        address[] memory spenders = new address[](3);
        spenders[0] = spenderA;
        spenders[1] = spenderB;
        spenders[2] = spenderC;
        uint256 gasUsed = _measureTouches(3, _repeat(address(tokenB)), spenders);
        emit log_named_uint("three actions, distinct approvals", gasUsed);
    }

    function testGasThreeActionsWithDistinctTokensAndApprovals() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenB);
        tokens[1] = address(tokenC);
        tokens[2] = address(tokenD);
        address[] memory spenders = new address[](3);
        spenders[0] = spenderA;
        spenders[1] = spenderB;
        spenders[2] = spenderC;
        uint256 gasUsed = _measureTouches(3, tokens, spenders);
        emit log_named_uint("three actions, distinct tokens and approvals", gasUsed);
    }

    function _assertAtomicFailure(uint256 failureIndex) internal {
        _prepareUserFunding();
        (address[] memory handlers, bytes[] memory datas) = _comboWithFailure(failureIndex);
        bytes memory nested =
            abi.encodeWithSelector(AssessmentHandler.ForcedFailure.selector, failureIndex);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoanHandler.InnerActionFailed.selector, failureIndex, nested
            )
        );
        vm.prank(user);
        executor.execute(handlers, datas);

        assertEq(recorder.length(), 0);
        assertEq(usdc.balanceOf(user), PREMIUM);
        assertEq(usdc.balanceOf(address(executor)), 0);
        assertEq(tokenB.balanceOf(user), 0);
        assertEq(tokenB.balanceOf(address(executor)), 0);
        assertEq(usdc.allowance(user, address(executor)), PREMIUM);
        assertEq(usdc.allowance(address(executor), pool), 0);
        assertEq(tokenB.allowance(address(executor), spenderA), 0);
    }

    function _measureTouches(
        uint256 actionCount,
        address[] memory tokens,
        address[] memory spenders
    ) internal returns (uint256 gasUsed) {
        _prepareUserFunding();
        (address[] memory handlers, bytes[] memory datas) =
            _touchCombo(actionCount, tokens, spenders, address(0));
        vm.prank(user);
        uint256 gasBefore = gasleft();
        executor.execute(handlers, datas);
        gasUsed = gasBefore - gasleft();
    }

    function _executeTouches(
        address[] memory tokens,
        address[] memory spenders,
        address recorderAddress
    ) internal {
        _prepareUserFunding();
        (address[] memory handlers, bytes[] memory datas) =
            _touchCombo(3, tokens, spenders, recorderAddress);
        vm.prank(user);
        executor.execute(handlers, datas);
    }

    function _prepareUserFunding() internal {
        usdc.mint(user, PREMIUM);
        vm.prank(user);
        usdc.approve(address(executor), PREMIUM);
    }

    function _touchCombo(
        uint256 actionCount,
        address[] memory tokens,
        address[] memory spenders,
        address recorderAddress
    ) internal view returns (address[] memory handlers, bytes[] memory datas) {
        address[] memory innerHandlers = new address[](actionCount + 1);
        bytes[] memory innerDatas = new bytes[](actionCount + 1);
        for (uint256 i; i < actionCount; ++i) {
            innerHandlers[i] = address(assessmentHandler);
            innerDatas[i] = abi.encodeCall(
                AssessmentHandler.touch,
                (MockERC20(tokens[i]), spenders[i], 1, recorderAddress, i + 1)
            );
        }
        innerHandlers[actionCount] = address(fundsHandler);
        innerDatas[actionCount] = abi.encodeCall(HandlerFunds.addFunds, (address(usdc), PREMIUM));
        return _outerCombo(innerHandlers, innerDatas);
    }

    function _comboWithFailure(uint256 failureIndex)
        internal
        view
        returns (address[] memory handlers, bytes[] memory datas)
    {
        address[] memory innerHandlers = new address[](4);
        bytes[] memory innerDatas = new bytes[](4);
        for (uint256 i; i < 3; ++i) {
            innerHandlers[i] = address(assessmentHandler);
            innerDatas[i] = i == failureIndex
                ? abi.encodeCall(AssessmentHandler.fail, (i))
                : abi.encodeCall(
                    AssessmentHandler.touch, (tokenB, spenderA, 1, address(recorder), i + 1)
                );
        }
        innerHandlers[3] = address(fundsHandler);
        innerDatas[3] = abi.encodeCall(HandlerFunds.addFunds, (address(usdc), PREMIUM));
        return _outerCombo(innerHandlers, innerDatas);
    }

    function _outerCombo(address[] memory innerHandlers, bytes[] memory innerDatas)
        internal
        view
        returns (address[] memory handlers, bytes[] memory datas)
    {
        handlers = new address[](1);
        datas = new bytes[](1);
        handlers[0] = address(flashLoanHandler);
        datas[0] = abi.encodeCall(
            FlashLoanHandler.flashLoan, (address(usdc), BORROW_AMOUNT, innerHandlers, innerDatas)
        );
    }

    function _repeat(address value) internal pure returns (address[] memory values) {
        values = new address[](3);
        values[0] = value;
        values[1] = value;
        values[2] = value;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract MockPool {
    uint256 internal constant PREMIUM = 500;

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16
    ) external {
        MockERC20(asset).mint(receiverAddress, amount);
        bool completed = IFlashLoanSimpleReceiver(receiverAddress)
            .executeOperation(asset, amount, PREMIUM, receiverAddress, params);
        require(completed, "callback failed");
        require(
            IERC20(asset).transferFrom(receiverAddress, address(this), amount + PREMIUM),
            "repayment failed"
        );
    }
}

contract AssessmentHandler is HandlerBase {
    using SafeERC20 for IERC20;

    error ForcedFailure(uint256 index);

    function touch(
        MockERC20 token,
        address spender,
        uint256 mintAmount,
        address recorder,
        uint256 marker
    ) external {
        _trackToken(address(token));
        token.mint(address(this), mintAmount);
        IERC20(address(token)).forceApprove(spender, 1);
        _trackApproval(address(token), spender);
        if (recorder != address(0)) OrderRecorder(recorder).record(marker);
    }

    function fail(uint256 index) external pure {
        revert ForcedFailure(index);
    }
}

contract OrderRecorder {
    uint256[] internal markers;

    function record(uint256 marker) external {
        markers.push(marker);
    }

    function length() external view returns (uint256) {
        return markers.length;
    }

    function at(uint256 index) external view returns (uint256) {
        return markers[index];
    }
}
