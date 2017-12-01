const FND = artifacts.require('./token/FundRequestToken.sol');
const TGE = artifacts.require('./crowdsale/FundRequestTokenGeneration.sol');
const TokenFactory = artifacts.require('./factory/MiniMeTokenFactory.sol');

const expect = require('chai').expect;
const log = console.log;

contract('FundRequestTokenGeneration', function (accounts) {

  let fnd;
  let tge;
  let tokenFactory;
  let owner = accounts[0];
  let founderWallet = accounts[1];
  let advisorWallet = accounts[2];
  let ecoSystemWallet = accounts[3];
  let coldStorageWallet = accounts[4];
  let tokenBuyer = accounts[5];

  beforeEach(async function () {
    tokenFactory = await TokenFactory.new();
    fnd = await FND.new(tokenFactory.address, 0x0, 0, "FundRequest", 18, "FND", true);
    await fnd.changeController(owner);
    await fnd.generateTokens(owner, 666000000000000000000);
    tge = await TGE.new(fnd.address, founderWallet, advisorWallet, ecoSystemWallet, coldStorageWallet, 1800);
    await fnd.changeController(tge.address);
  });

  it('should be possible to buy tokens', async function () {
    await buyTokens(1);
    await expectBalance(tokenBuyer, 1800);
  });

  it('should mint founder tokens when tokens are bought', async function () {
    await buyTokens(1);
    await expectBalance(founderWallet, 810);
  });

  it('should mint advisor tokens when tokens are bought', async function () {
    await buyTokens(1);
    await expectBalance(advisorWallet, 90);
  });

  it('should mint ecosystem tokens when tokens are bought', async function () {
    await buyTokens(1);
    await expectBalance(ecoSystemWallet, 1350);
  });

  it('should mint cold storage tokens when tokens are bought', async function () {
    await buyTokens(1);
    await expectBalance(coldStorageWallet, 450);
  });

  it('should update deposits when tokens are bought', async function () {
    await buyTokens(1);
    let deposits = await tge.deposits.call(tokenBuyer);
    expect(deposits.toNumber()).to.equal(getAmountInWei(1));
  });

  it('should update investorsCount when tokens are bought', async function () {
    await buyTokens(1);
    let count = await tge.investorCount.call();
    expect(count.toNumber()).to.equal(1);
  });

  it('should update investors when tokens are bought', async function () {
    await buyTokens(1);
    let investor = await tge.investors.call(0);
    expect(investor).to.equal(tokenBuyer);
  });

  it('should update weiRaised count when tokens are bought', async function () {
    await buyTokens(1);
    let wei = await tge.weiRaised.call();
    expect(wei.toNumber()).to.equal(getAmountInWei(1));
  });

  let buyTokens = async function (amountInEther) {
    amountInEther = amountInEther || 1;
    await tge.proxyPayment(tokenBuyer, {value: getAmountInWei(amountInEther)});
  };

  let expectBalance = async function (address, amount) {
    let balance = await fnd.balanceOf.call(address);
    expect(balance.toNumber()).to.equal(getAmountInWei(amount));
  };

  let getAmountInWei = function (number) {
    return number * Math.pow(10, 18);
  };


  function assertInvalidOpCode(error) {
    assert(
      error.message.indexOf('invalid opcode') >= 0,
      'transfer should throw an opCode exception.'
    );
  }


});