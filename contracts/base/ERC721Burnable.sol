// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import "./ERC721Base.sol";

contract ERC721Burnable is ERC721Base {

    constructor(string memory _name, string memory _symbol) ERC721Base(_name, _symbol) {}

    function burn(uint256 _id) external virtual {
        address tokenOwner = ownerOf(_id);

        require(tokenOwner != address(0), "Invalid Id");
        require(msg.sender == tokenOwner || isApprovedForAll[tokenOwner][msg.sender] || msg.sender == getApproved[_id], "NOT_AUTHORIZED");
        
        _burn(_id);
    }
}
