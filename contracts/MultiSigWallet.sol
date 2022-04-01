// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.10;

contract MultiSigWalet {
    event Deposit(address indexed sender, uint amount);
    event Submit(uint indexed txId);  // submit tx and waiting other to approve
    event Approve(address indexed owner, uint indexed txId); // approve tx
    event Revoke(address indexed owner, uint indexed txId);  // revoke or reject tx
    event Execute(uint indexed txId); // execute tx after all confirmation complete

    struct Transaction {
        address to; 
        uint value;
        bytes data;  // data to be sent to the address
        bool executed;  // true when tx is excuted
    }

    address[] public owners;
    mapping(address => bool) public isOwner;  // check that msg.sender is owner
    uint public required;  // number of approvals required before tx can be excuted

    Transaction[] public transactions;

    // each tx will can be executed if the number of approval >= required
    // approval of each tx by each owner to show tx is approved by owner or not
    mapping(uint => mapping(address => bool)) public approved;

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint _txId) {
        require(_txId < transactions.length, "tx does not exist");
        _;
    }

    modifier notApproved(uint _txId) {
        require(!approved[_txId][msg.sender], "tx already approved");   // checking with the approved mapping
        _;
    }

    modifier notExecuted(uint _txId) {
        require(!transactions[_txId].executed, "tx already executed");
        _;
    }

    constructor(address[] memory _owners, uint _required) {
        require(_owners.length > 0, "owners required");
        require(
            _required > 0 && _required <= _owners.length,
            "Invalid required number of owners"
        );

        // save the owners to state variable
        for (uint i; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "Invalid owner");      // owner cannot be 0x00000000...00
            require(!isOwner[owner], "owner is not unique");    // check if not exist in owner mapping

            isOwner[owner] = true;
            owners.push(owner);
        }

        required = _required;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function submit(address _to, uint _value, bytes calldata _data)
        external
        onlyOwner
    {
        transactions.push(Transaction({
            to: _to,
            value: _value,
            data: _data,
            executed: false
        })); 
        emit Submit(transactions.length - 1);   // txid is index where tx is strored
    }

    function approve(uint _txId)
        external
        onlyOwner
        txExists(_txId)
        notApproved(_txId) // check tx is not yet approved by msg.sender
        notExecuted(_txId)
    {
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
    }

    function _getApprovalCount(uint _txId) private view returns (uint count) {
        for (uint i; i < owners.length; i++) {
            if (approved[_txId][owners[i]]) {
                count++;
            }
        }
    }

    function execute(uint _txId) external txExists(_txId) notExecuted(_txId) {
        require(_getApprovalCount(_txId) >= required, "approvals less than required");
        Transaction storage transaction = transactions[_txId];

        transaction.executed = true;

        // call function: sending a message to contract and return tuple of a boolean and bytes array
        (bool sucess, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        require(sucess, "tx failed");

        emit Execute(_txId);
    }

    function revoke(uint _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
        // must be a first approver of the transaction
        require(approved[_txId][msg.sender], "tx not approve");
        approved[_txId][msg.sender] = false;
        emit Revoke(msg.sender, _txId);
    }
}