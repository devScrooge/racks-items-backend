// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol"; // define roles
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol"; // erc1155 tokens
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol"; // contract should be ERC1155 holder to receive ERC1155 tokens
import "@openzeppelin/contracts/token/ERC721/IERC721.sol"; // to instanciate MrCrypto object
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // to work with RacksToken
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol"; // to work with COORDINATOR and VRF
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol"; // to use functionalities for Chainlink VRF

contract RacksItemsv2 is ERC1155, ERC1155Holder, AccessControl, VRFConsumerBaseV2 { // VRFv2SubscriptionManager
   
  /**
  * @notice Enum for Contract state -> to let user enter call some functions or not
  */
  enum ContractState {   
    Active,
    Inactive
  }

  /**
  * @notice Struct for Items on the Marketplace
  */
  struct itemOnSale{
    uint256 tokenId;
    uint256 marketItemId;
    uint256 price;
    address seller;
    bool sold;
  }

  /**
  * @notice Struct for Tickets on the Marketplace
  */
  struct caseTicket {
    uint256 ticketId;
    uint256 numTries;
    uint256 duration;
    uint256 price;
    address owner;
    uint256 timeWhenSold;
    bool isAvaliable;
  }

  /// @notice tokens
  IERC721 MR_CRYPTO;
  address public constant i_MrCryptoAddress = 0xeF453154766505FEB9dBF0a58E6990fd6eB66969;
  IERC20 racksToken;
  
  /// @notice Standard variables
  bytes32 public constant ADMIN_ROLE = 0x00;
  address private _owner;
  uint256 private s_maxTotalSupply;
  uint256 private s_tokenCount;
  uint256 private _marketCount;
  uint256 private s_ticketCount;
  uint256 public casePrice; // Change to RacksToken
  bool public contractActive = true;
  ContractState public s_contractState;
  itemOnSale[] _marketItems;
  caseTicket[] _tickets;

  /// @notice VRF Variables
  VRFCoordinatorV2Interface public immutable i_vrfCoordinator; 
  bytes32 public immutable i_gasLane;
  uint64 public immutable i_subscriptionId;
  uint32 public immutable i_callbackGasLimit;
  uint16 public constant REQUEST_CONFIRMATIONS = 3; 
  uint32 public constant NUM_WORDS = 2; 
  uint256 public s_randomWord; // random Number we get from Chainlink VRF
  
  /// @notice Mappings
  mapping(address => bool) private s_gotRacksMembers;
  mapping(uint => uint) private s_maxSupply;
  mapping (uint256 => string) private s_uris; 
  mapping(address => bool) private s_isSellingTicket;
  mapping(address => bool) private s_hasTicket; 
  mapping(address => bool) private s_ticketIsLended;

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
  event ticketPriceChanged(address owner, uint256 newTries, uint256 newPrice);
  event ticketBought(uint256 ticketId, address oldOwner, address newOwner, uint256 price);
  event ticketClaimedBack(address borrower, address realOwner);
  
  /// @notice Modifiers
  /// @notice Check that person calling a function is the owner of the Contract
  modifier onlyOwner() {
    require(msg.sender == _owner, "User is not the owner");
      _;
  }

  /// @notice Check that user is Owner or Admin
  modifier onlyOwnerOrAdmin() {
    require(_isOwnerOrAdmin(msg.sender), "User is not the Owner or an Admin");
    _;
  }

  /// @notice Check that user is Member and owns at least 1 MrCrypto
  modifier onlyVIP() {
    require(isVip(msg.sender), "User is not RacksMembers or does not owns a MrCrypto");
      _;
  }

  /**  @notice Check that user is owns at least 1 ticket for opening case (used in case user
  * does not own a MrCrypto or RacksMember and buys a ticket from another user)
  */
  modifier ownsTicket() {
    require(s_hasTicket[msg.sender], "User does not owns a Ticket for openning the case.");
    _;
  }

  /// @notice Check if contract state is Active
  modifier contractIsActive() {
    require(s_contractState == ContractState.Active, "Contract is not active at this moment");
    _;
  }

  constructor(address vrfCoordinatorV2, bytes32 gasLane, uint64 subscriptionId, uint32 callbackGasLimit, address _racksTokenAddress) 
  VRFConsumerBaseV2(vrfCoordinatorV2)
  ERC1155(""){
    /**
    * Initialization of Chainlink VRF variables
    */
    i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2); 
    i_gasLane = gasLane; 
    i_subscriptionId = subscriptionId;
    i_callbackGasLimit = callbackGasLimit; 

    /**
    * Initialization of RacksItem contract variables
    */
    MR_CRYPTO = IERC721(i_MrCryptoAddress);
    racksToken = IERC20(_racksTokenAddress);
    _owner = msg.sender;
    s_tokenCount = 0;
    s_ticketCount = 0;
    casePrice = 1;
    s_contractState = ContractState.Active;

    /**
    * Mint of initial supply
    _mintSupply(address(this), 100000); // Jeans
    _mintSupply(address(this), 1000); // Hoddie 
    _mintSupply(address(this), 50000); // Watch
    _mintSupply(address(this), 1000); // Coat
    _mintSupply(address(this), 30000); // Shoes
     */
  }

  /** 
  * @notice Need to override supportsInterface function because Contract is ERC1155 and AccessControl
  */
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC1155Receiver, AccessControl) returns (bool) {
    return super.supportsInterface(interfaceId);
  }


  // FUNCTIONS RELATED WITH THE CASE

  /**
  * @notice Change price of the box
  * @dev Only callable by the Owner
  */
  function setCasePrice(uint256 price) public onlyOwnerOrAdmin {
    casePrice = price;
    emit casePriceChanged(price);
  }

  /**
  * @notice View case price
  */
  function getCasePrice() public view returns(uint256) {
    return casePrice;
  }

  /**
  * @notice Used to get an actually Random Number -> to pick an item when openning a case
  * @dev Uses Chainlink VRF -> call requestRandomWords method by using o_vrfCoordinator object
  * set as internal because is going to be called only when a case is opened
  */
  function _randomNumber() public returns(uint256) {
  uint256 s_requestedNumber = i_vrfCoordinator.requestRandomWords(i_gasLane, i_subscriptionId, REQUEST_CONFIRMATIONS, i_callbackGasLimit, NUM_WORDS);
  return s_requestedNumber;
  }

  /**
  * @notice Function to actually pick a winner 
  * @dev 
  * - randomWords -> array of randomWords
  */
  function fulfillRandomWords(uint256 /* requestId */, uint256[] memory randomWords) internal override {
    s_randomWord = randomWords[0]; // just in case random number is very long we apply modular function 
  }

   /**
  * @notice Function used to 'open a case' and get an item
  * @dev 
  * - Should check that user owns a Ticket -> modifier
  * - Should check that msg.value is bigger than casePrice
  * - Should transfer msg.value to the contract
  * - Internally calls randomNumber() 
  * - Apply modular function for the randomNumber to be between 0 and totalSupply of items
  * - Should choose an item
  */
  function openCase() public /*ownsTicket*/ contractIsActive {  
    racksToken.transferFrom(msg.sender, address(this), casePrice);
    uint256 randomNumber = _randomNumber()  % s_maxTotalSupply;
    uint256 totalCount = 0;
    uint256 item;

    for(uint256 i = 0 ; i < s_tokenCount; i++) {
      uint256 _newTotalCount = totalCount + s_maxSupply[i] ;
      if(randomNumber > _newTotalCount) {
        totalCount = _newTotalCount;
      }else {
        item = i;
        if(balanceOf(address(this),item)==0){
          for(uint256 j = item-1; j >= 0; j--){
            if (balanceOf(address(this),j)>0){
              item = j;
              break;
            }
          }
        }
        _safeTransferFrom(address(this), msg.sender, item , 1,"");
        break;
      }
    }
    decreaseTicketTries(msg.sender);
    emit CaseOpened(msg.sender, casePrice, item);
  }


  // FUNCTIONS RELATED TO ITEMS

  /**
  * @notice Returns maxSupply of specific item (by tokenId)
  * @dev - Getter of s_maxSupply mapping
  */
  function supplyOfItem(uint256 tokenId) public view returns(uint) {
    return s_maxSupply[tokenId];
  }

  /**
  * @notice Check that item exists (by tokenId)
  */
  function _itemExists(uint256 tokenId) internal view returns (bool) {
    require(s_maxSupply[tokenId] > 0);
    return true;
  }

  /**
  * @notice Calculate chance of receiving an specific item
  * - As higher is result higher is the rarity of the item
  * @dev - Requires that tokenId exists (item is listed)
  * - chance is calculated as item supply divided by total items supply
  */
  function _rarityOfItem(uint256 tokenId) public virtual view returns(uint256) {
    require(_itemExists(tokenId));
    uint256 result = s_maxTotalSupply / s_maxSupply[tokenId];
    return result;
  }

  /**
  * @notice Returns all the items inside the user's inventory (Could be used by the
  * user to check his inventory or to check someone else inventory by address)
  * @dev Copy users inventory in an empty array and returns it
  */
  function viewItems(address owner) public view returns(uint256[] memory) { 
    uint256[] memory inventory = new uint [](s_tokenCount);
    for(uint256 i=0 ; i<inventory.length; i++) {
      inventory[i]=balanceOf(owner,i);
    }
    return inventory;
  }

  /**
  * @notice List a new item to the avaliable collection
  * @dev Only callable by the Owner
  */
  function listItem(uint256 itemSupply) public onlyOwnerOrAdmin {
    _mintSupply(address(this), itemSupply);
  }

  /**
  * @notice Mint supply tokens of each Item
  * @dev Declared internal because it is called inside the contructor
  * - call _mint function
  * - call set maxSupply function
  * - updates TotalMaxSupply of Items
  * - updates s_tokenCount -> Each items has associated an Id (e.g: Jeans -> Id: 0, Hoddie -> Id: 1,
  * we increment s_tokenCount so next time we call _mintSupply a new type of item is going to be minted)
  * - The items (tokens are minted by this contract and deposited into this contract address)
  */
  function _mintSupply(address receiver, uint256 amount) internal {
      _mint(receiver, s_tokenCount, amount, "");
      _setMaxSupply(s_tokenCount, amount);
      s_maxTotalSupply += amount;
      s_tokenCount += 1;
  }

  /**
  * @notice Function used to set maxSupply of each item
  */
  function _setMaxSupply(uint256 tokenId, uint256 amount) internal {
      s_maxSupply[tokenId] = amount;
  }


  // FUNCTIONS RELATED TO THE "MARKETPLACE"

  /**
  * @notice Function used to sell an item on the marketplace
  * @dev
  * - Needs to check balanceOf item trying to be sold
  * - Needs to transfer item 
  * - Update marketItems array
  * - Emit event 
  */
  function sellItem(uint256 marketItemId, uint256 price) public {
    require(balanceOf(msg.sender, marketItemId) > 0, "Item not found.");
    _safeTransferFrom(msg.sender, address(this), marketItemId, 1 ,"");
    _marketItems.push(
      itemOnSale(
        marketItemId,
        _marketCount,
        price,
        msg.sender,
        false
      )
    );
    _marketCount++;
    emit sellingItem(msg.sender, marketItemId, price);
  }

  /**
  * @notice Function used to unlist an item from marketplace
  * @dev
  * - Needs to check that user is trying to unlist an item he owns
  * - Needs to transfer item from contract to user address
  * - Update item's sold variable
  * - Emit event
  */
  function unListItem(uint256 marketItemId) public {
    require(_marketItems[marketItemId].seller == msg.sender, "You are not the owner of this item.");
    _safeTransferFrom(address(this), msg.sender, marketItemId, 1, "");
    _marketItems[marketItemId].sold = true;
    emit unListedItem(msg.sender, marketItemId);
  }

  /**
  * @notice Function used to change price from item listed 
  * @dev
  * - Needs to check that user is trying to unlist an item he owns
  * - Needs to update price status
  * - Emit event
  */
  function changeItemPrice(uint256 marketItemId, uint256 newPrice) public {
    require(_marketItems[marketItemId].seller == msg.sender, "You are not the owner of this item.");
    uint256 oldPrice = _marketItems[marketItemId].price;
    _marketItems[marketItemId].price = newPrice;
    emit itemPriceChanged(msg.sender, marketItemId, oldPrice, newPrice);
  }

  /**
  * @notice Function used to exchange a token item for a real physical clothe.
  */
  function exchangeItem(uint256 marketItemId) public {
    require(balanceOf(msg.sender, marketItemId) > 0);
     _burn(msg.sender, marketItemId, 1);
     s_maxSupply[marketItemId] -= 1;
     s_maxTotalSupply -=1;
     emit itemExchanged(msg.sender, marketItemId);
  }

  /**
  * @notice Function used to buy an item on the marketplace
  * @dev
  * - Needs to check that user is not trying to buy its own item
  * - Needs to check that item was not sold before
  * - Needs to transfer tokens from buyer to seller
  * - Needs to transfer item from seller to buyer
  * - Update sold attribute from array
  * - Emit event 
  */
  function buyItem(uint256 marketItemId) public {
    itemOnSale memory item = _marketItems[marketItemId];
    require(msg.sender!=item.seller);
    require(item.sold==false);
    racksToken.transferFrom(msg.sender, item.seller, item.price);
    _safeTransferFrom(address(this), msg.sender, item.tokenId, 1 ,"");
    _marketItems[marketItemId].sold = true;
    emit itemBought(msg.sender, item.seller, marketItemId, item.price);
  }

  /**
  * @notice Function used to return items that are currently on sale
  */
  function getMarketItem(uint marketItemId) public view returns(itemOnSale memory){
    return _marketItems[marketItemId];
  }

  /**
  * @notice function used to return every item that is on sale on the MarketPlace
  */
  function getItemsOnSale() public view returns(itemOnSale[] memory) {
    uint arrayLength;
    
    for(uint i=0; i<_marketItems.length;i++){
      itemOnSale memory item = _marketItems[i];
      if(item.sold==false){
        arrayLength+=1;
      }
    }
    itemOnSale[] memory items = new itemOnSale[](arrayLength);
    uint indexCount;
    for(uint256 i = 0; i < _marketItems.length; i++){
      itemOnSale memory  item = _marketItems[i];
      if(item.sold==false){
        items[indexCount]=item;
        indexCount++;
      }
    }
    return items;
  }

  // FUNCTIONS RELATED TO "TICKETS"

  /**
  * @notice This function is used for a VIP user to list 'Case Tickets' on the MarketPlace
  * @dev - Should check that user is Vip (Modifier)
  * - Should check that user is NOT currently selling another ticket -> Users can only sell 1 ticket at the same time
  * - Include ticket on array
  * - Increase s_ticketCount
  * - Set mapping to true
  * - Emit event
  *
  */
  function listTicket(uint256 numTries, uint256 _hours, uint256 price) public onlyVIP {
    require(!s_isSellingTicket[msg.sender], "User is already currently selling a Ticket");
    require(s_hasTicket[msg.sender], "User has ticket avaliable");
    _tickets.push(
      caseTicket(
      s_ticketCount,
      numTries,
      _hours,
      price,
      msg.sender,
      0,
      true
    ));
    s_ticketCount++;
    s_isSellingTicket[msg.sender] = true;
    emit newTicketOnSale(msg.sender, numTries, _hours, price);
  }

  /**
  * @notice This function is used for a VIP user to unlist 'Case Tickets' on the MarketPlace
  * @dev - Should check that user is Vip (Modifier)
  * - Should check that user has a listed ticket
  * - Emit event
  */
  function unListTicket(uint256 ticketId) public onlyVIP {
    require(s_isSellingTicket[msg.sender], "User is not currently selling a Ticket");
    require(_tickets[ticketId].owner == msg.sender, "User is not owner of this ticket");
    _tickets[ticketId].isAvaliable = false;
    s_isSellingTicket[msg.sender] = false;
    emit unListTicketOnSale(msg.sender);
  }

    /**
  * @notice This function is used for a VIP user to change 'Case Tickets' price and tries on the MarketPlace
  * @dev - Should check that user is Vip (Modifier)
  * - Should check that user has a listed ticket
  * - Emit event
  */
  function changeTicketConditions(uint256 ticketId, uint256 newTries, uint256 newPrice) public onlyVIP {
    require(s_isSellingTicket[msg.sender], "User is not currently selling a Ticket");
    require(_tickets[ticketId].owner == msg.sender, "User is not owner of this ticket");
    _tickets[ticketId].price = newPrice;
    _tickets[ticketId].numTries = newTries;
    emit ticketPriceChanged(msg.sender, newTries, newPrice);
  }

    /**
  * @notice This function is used to buy a caseTicket
  * @dev - Should check that user is NOT Vip -> does make sense that a VIP user buys a ticket
  * - Should check that user has a listed ticket
  * - Transfer RacksToken from buyer to seller
  * - Update mappings variables
  * - Emit event
  */
  function buyTicket(uint256 ticketId) public {
    require(!isVip(msg.sender));
    require(_tickets[ticketId].owner != msg.sender, "You can not buy a ticket to your self");
    require(_tickets[ticketId].isAvaliable == true, "Ticket is not currently avaliable");
    address oldOwner = _tickets[ticketId].owner;
    racksToken.transferFrom(msg.sender, _tickets[ticketId].owner, _tickets[ticketId].price);
    _tickets[ticketId].timeWhenSold = block.timestamp;
    s_hasTicket[_tickets[ticketId].owner] = false;
    s_isSellingTicket[_tickets[ticketId].owner] = false;
    s_ticketIsLended[_tickets[ticketId].owner] = true;
    _tickets[ticketId].owner = msg.sender;
    s_hasTicket[msg.sender] = true;
    emit ticketBought(ticketId, oldOwner, msg.sender, _tickets[ticketId].price);
  }

  /** @notice Function used to claim Ticket back when duration is over
  * @dev - Check that claimer is lending a Ticket
  * - Check that duration of the Ticket is over -> block.timestamp is in seconds and duration in hours 
  * -> transform duration into seconds 
  * - Update mappings
  * - Emit event
  */
  function claimTicketBack(uint256 ticketId) public onlyVIP {
    require(s_ticketIsLended[msg.sender], "User did not sell any Ticket");
    require((_tickets[ticketId].timeWhenSold - block.timestamp) > (_tickets[ticketId].duration) / 60, "Duration of the Ticket is still avaliable");
    s_hasTicket[_tickets[ticketId].owner] = false;
    s_hasTicket[msg.sender] = true;
    s_ticketIsLended[msg.sender] = false;
    emit ticketClaimedBack(_tickets[ticketId].owner, msg.sender);
  }
  
  /** @notice Function used to decrease Ticket tries avaliables
  * @dev - Check if used trie was last one
  *        - If not: just decrease numTries
  *        - If so: decrease numTries, update Avaliability and mappings
  */
  function decreaseTicketTries(address user) public {
    for (uint256 i = 0; i < _tickets.length; i++) {
        if (_tickets[i].owner == user) {
            if(_tickets[i].numTries != 1) { // Case it was not the last trie avaliable
                _tickets[i].numTries--;
            }else { // it was his last trie avaliable
                _tickets[i].numTries--;
                _tickets[i].isAvaliable = false;
                s_hasTicket[user] = false;
        }
     } 
    } 
  }

  /**
  * @notice Function used to return ticket that are currently on sale
  */
  function getMarketTicket(uint ticketId) public view returns(caseTicket memory) {
    return _tickets[ticketId];
  }

  /**
  * @notice Function used to return every ticket that are currently on sale
  */
   function getITicketsOnSale() public view returns(caseTicket[] memory) {
    uint arrayLength;
    
    for(uint i=0; i<_tickets.length;i++){
      caseTicket memory ticket = _tickets[i];
      if(ticket.isAvaliable==true){
        arrayLength+=1;
      }
    }
    caseTicket[] memory tickets = new caseTicket[](arrayLength);
    uint indexCount;
    for(uint256 i = 0; i < _tickets.length; i++){
      caseTicket memory ticket = _tickets[i];
      if(ticket.isAvaliable==true){
        tickets[indexCount]=ticket;
        indexCount++;
      }
    }
    return tickets;
  }

  // FUNCTIONS RELATED TO "USERS"

  /**
  * @notice Check if user is RacksMembers and owns at least 1 MrCrypto
  * @dev - Require users MrCrypro's balance is > '
  * - Require that RacksMembers user's attribute is true
  */
  function isVip(address user) public view returns(bool){
    require(MR_CRYPTO.balanceOf(user) > 0);
    require(s_gotRacksMembers[user]);
    return true;
  }

  /**
  * @notice Check if user is owner of the Contract or has admin role
  * @dev Only callable by the Owner
  */
  function _isOwnerOrAdmin(address user) internal view returns (bool) {
      require(_owner == user || hasRole(ADMIN_ROLE, user));
      return true;
  }

  /**
  * @notice Set RacksMember attribute as true for a user that is Member
  * @dev Only callable by the Owner
  * Require comented because maybe owner or admin are trying to set as true some address that was already set as true
  */
  function setSingleRacksMember(address user) public onlyOwnerOrAdmin {
    //require(!s_gotRacksMembers[user], "User is already RacksMember");
    s_gotRacksMembers[user] = true;
  }

  /**
  * @notice Set RacksMember attribute as true for a list of users that are Members (array)
  * @dev Only callable by the Owner
  * Require comented because maybe owner or admin are trying to set as true some address that was already set as true
  */
  function setListRacksMembers(address[] memory users) public onlyOwnerOrAdmin {
    for (uint256 i = 0; i < users.length; i++) {
      //require(!s_gotRacksMembers[users[i]], "User is already RacksMember");
       s_gotRacksMembers[users[i]] = true;
    }
  }

  /**
  * @notice Set RacksMember attribute as false for a user that was Racks Member before but it is not now
  * @dev Only callable by the Owner
  * Require comented because maybe owner or admin are trying to set as false some address that was already set as false
  */
  function removeSingleRacksMember(address user) public onlyOwnerOrAdmin {
    //require(s_gotRacksMembers[user], "User is already not RacksMember");
    s_gotRacksMembers[user] = false;
  }

  /**
  * @notice Set RacksMember attribute as false for a list of users that are Members (array)
  * @dev Only callable by the Owner
  * Require comented because maybe owner or admin are trying to set as false some address that was already set as false
  */
  function removeListRacksMembers(address[] memory users) public onlyOwnerOrAdmin {
    for (uint256 i = 0; i < users.length; i++) {
      //require(s_gotRacksMembers[users[i]], "User is already not RacksMember");
      s_gotRacksMembers[users[i]] = false;
    }
  }

  /**
  * @notice Set new Admin
  * @dev Only callable by the Owner
  */
  function setAdmin(address _newAdmin) public onlyOwner {
    _setupRole(ADMIN_ROLE, _newAdmin);
  }

  // FUNCTIONS RELATED WITH THE CONTRACT

  /**
  * @notice Change contract state from Active to Inactive and viceversa
  * @dev Only callable by the Owner or an admin
  */
  function flipContractState() public onlyOwnerOrAdmin {
    if (s_contractState == ContractState.Active) {
      s_contractState = ContractState.Inactive;
    }else {
      s_contractState = ContractState.Active;
    }
  }

  // FUNCTIONS RELATED TO ERC1155 TOKENS

  /**
  * @notice Used to return token URI by inserting tokenID
  * @dev - returns information stored in s_uris mapping
  * - Any user can check this information
  */
  function uri(uint256 tokenId) override public view returns (string memory) {
    return(s_uris[tokenId]);
  }

  /**
  * @notice Used to set tokenURI to specific item 
  * @dev - Only Owner or Admins can call this function
  * - Need to specify:
  *  - tokenId: specific item you want to set its uri
  *  - uri: uri wanted to be set
  */
  function setTokenUri(uint256 tokenId, string memory _uri) public onlyOwnerOrAdmin {
      require(bytes(s_uris[tokenId]).length == 0, "Can not set uri twice"); 
      s_uris[tokenId] = _uri; 
  }

  
  // FUNCTIONS RELATED TO FUNDS
  
  /**
  * @notice Used to withdraw specific amount of funds
  * @dev 
  * - Only owner is able to call this function
  * - Should check that there are avaliable funds to withdraw
  * - Should specify the wallet address you want to transfer the funds to
  * - Should specify the amount of funds you want to transfer
  */
  function withdrawFunds(address wallet, uint256 amount) public onlyOwner {
    require(racksToken.balanceOf(address(this)) > 0, "No funds to withdraw");
    racksToken.transfer(wallet, amount);
  }

  /**
  * @notice Used to withdraw ALL funds
  * @dev 
  * - Only owner is able to call this function
  * - Should check that there are avaliable funds to withdraw
  * - Should specify the wallet address you want to transfer the funds to
  */
  function withdrawAllFunds(address wallet) public onlyOwner {
    require(racksToken.balanceOf(address(this)) > 0, "No funds to withdraw");
    racksToken.transfer(wallet, address(this).balance);
  }

  /// @notice Receive function
  receive() external payable {
  }
}