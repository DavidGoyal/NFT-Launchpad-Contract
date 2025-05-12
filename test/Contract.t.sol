// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/Contract.sol";

contract TestContract is Test {
    HypurrBlades c;

    function setUp() public {
        c = new HypurrBlades("HypurrBlades","Blades",0xC604589f651bfb2515a408bc1C1013dcb707702C,500,0xC604589f651bfb2515a408bc1C1013dcb707702C,200);
    }

    function testBar() public {
        assertEq(uint256(1), uint256(1), "ok");
    }

    function testFoo(uint256 x) public {
        vm.assume(x < type(uint128).max);
        assertEq(x + x, x * 2);
    }
}
