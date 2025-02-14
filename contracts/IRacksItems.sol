// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ITickets.sol";

interface IRacksItems { 

    /**
    * @notice Struct for Items on the Marketplace
    */
    struct itemOnSale{
    uint256 tokenId;
    uint256 marketItemId;
    uint256 price;
    address itemOwner;
    bool isOnSale;
    }

    /// @notice Events
    event CaseOpened(address user, uint256 casePrice, uint256 item);
    event casePriceChanged(uint256 newPrice);
    event itemExchanged(address user, uint256 tokenId);
    event sellingItem(address user, uint256 tokenId, uint256 price);
    event itemBought(address buyer, address seller, uint256 marketItemId, uint256 price);
    event unListedItem(address owner, uint256 marketItemId);
    event itemPriceChanged(address owner, uint256 marketItemId, uint256 oldPrice, uint256 newPrice);
    event newTicketOnSale(address seller, uint256 numTries, uint256 _hours, uint256 price);
    event unListTicketOnSale(address owner);
    event ticketConditionsChanged(address owner, uint256 newTries, uint256 newHours, uint256 newPrice);
    event ticketBought(uint256 ticketId, address oldOwner, address newOwner, uint256 price);
    event ticketClaimedBack( address realOwner);

    function openCase() external returns(bool success);

    function fulfillCaseRequest(address _user,  uint _randomNumber) external;

    function caseLiquidity() external view returns(uint256[] memory);

    function supplyOfItem(uint256 tokenId) external view returns(uint);


    function viewItems(address owner) external view returns(uint256[] memory);

    function listItemOnMarket(uint256 marketItemId, uint256 price) external;

    function unListItem(uint256 marketItemId) external;

    function changeItemPrice(uint256 marketItemId, uint256 newPrice) external;

    function exchangeItem(uint256 tokenId) external;

    function buyItem(uint256 marketItemId) external;

    function getItemsOnSale() external view returns(itemOnSale[] memory);

    function listTicketFrom(address from, uint256 numTries, uint256 _hours, uint256 price) external;

    function unListTicketFrom(address from) external;

    function changeTicketConditionsFrom( address from, uint256 newTries, uint256 newHours, uint256 newPrice) external;

    function buyTicket(uint256 ticketId) external;

    function claimTicketBackFrom(address from) external;

    function approveForTickets( address spender, bool permission) external;

    function ticketAllowance(address owner, address spender) external view returns(bool);

    function isApproved(address user) external view returns(bool);

    function getMarketTicket(uint256 ticketId) external view;

    function getTicketsOnSale() external view returns(ITickets.caseTicket[] memory);

    function getUserTicket(address user) external view returns(uint256 durationLeft, uint256 triesLeft, uint ownerOrSpender, uint256 ticketPrice);

    function isVip(address user) external view returns(bool);

    function setAdmin(address _newAdmin) external;

    function setTokenUri(uint256 tokenId, string memory _uri) external;

    function withdrawFunds(address wallet, uint256 amount) external;

    function withdrawAllFunds(address wallet) external;
}