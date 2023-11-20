#include "perf_cnt.h"

volatile unsigned long* const Cycle_count = (void *)0x60010000;
volatile unsigned long* const Inst_count = (void *)0x60010008;
volatile unsigned long* const mr_inst_count = (void *)0x60011000;
volatile unsigned long* const mw_inst_count = (void *)0x60011008;
volatile unsigned long* const inst_req_delay_cycle = (void *)0x60012000;
volatile unsigned long* const inst_delay_cycle = (void *)0x60012008;
volatile unsigned long* const mr_req_delay_cycle = (void *)0x60013000;
volatile unsigned long* const rdw_delay_cycle = (void *)0x60013008;
volatile unsigned long* const mw_req_delay_cycle = (void *)0x60014000;
volatile unsigned long* const branch_inst_count = (void *)0x60014008;
volatile unsigned long* const jump_inst_count = (void *)0x60015000;


unsigned long _uptime() {
  // TODO [COD]
  //   You can use this function to access performance counter related with time or cycle.
  return *(volatile unsigned long *)Cycle_count;
}

unsigned long _inst_cnt() {
  // TODO [COD]
  //   You can use this function to count the number of instruction, which can be used to calculate cycle per instruction.
  return *(volatile unsigned long *)Inst_count;
}

unsigned long _mr_cnt() {
  // TODO [COD]
  //   You can use this function to count the number of mem_read instruction, which can be used to access performance when reading data from Memory.
  return *(volatile unsigned long *)mr_inst_count;
}

unsigned long _mw_cnt() {
  // TODO [COD]
  //   You can use this function to count the number of mem_write instruction, which can be used to access performance when writing data to Memory.
  return *(volatile unsigned long *)mw_inst_count;
}

unsigned long _inst_req_delay_cycle() {
  // TODO [COD]
  //   You can use this function to count the number of cycles delayed after sending fetch instruction requests.
  return *(volatile unsigned long *)inst_req_delay_cycle;
}

unsigned long _inst_delay_cycle() {
  // TODO [COD]
  //   You can use this function to count the number of cycles delayed to fetch instructions.
  return *(volatile unsigned long *)inst_delay_cycle;
}

unsigned long _mr_req_delay_cycle() {
  // TODO [COD]
  //   You can use this function to count the number of cycles delayed after sending requests of reading data rom memory.
  return *(volatile unsigned long *)mr_req_delay_cycle;
}

unsigned long _rdw_delay_cycle() {
  // TODO [COD]
  //   You can use this function to count the number of cycles delayed to get data rom memory.
  return *(volatile unsigned long *)rdw_delay_cycle;
}

unsigned long _mw_req_delay_cycle() {
  // TODO [COD]
  //   You can use this function to count the number of cycles delayed after sending requests of writing data to memory.
  return *(volatile unsigned long *)mw_req_delay_cycle;
}

unsigned long _branch_inst_cnt() {
  // TODO [COD]
  //   You can use this function to count the number of branch instruction.
  return *(volatile unsigned long *)branch_inst_count;
}

unsigned long _jump_inst_cnt() {
  // TODO [COD]
  //   You can use this function to count the number of jump instruction.
  return *(volatile unsigned long *)jump_inst_count;
}


void bench_prepare(Result *res) {
  // TODO [COD]
  //   Add preprocess code, record performance counters' initial states.
  //   You can communicate between bench_prepare() and bench_done() through
  //   static variables or add additional fields in `struct Result`
  res->msec = _uptime();

  res->inst_cnt = _inst_cnt();
  res->mr_cnt = _mr_cnt();
  res->mw_cnt = _mw_cnt();
  res->inst_req_delay_cnt = _inst_req_delay_cycle();
  res->inst_delay_cnt = _inst_delay_cycle();
  res->mr_req_delay_cnt = _mr_req_delay_cycle();
  res->rdw_delay_cnt = _rdw_delay_cycle();
  res->mw_req_delay_cnt = _mw_req_delay_cycle();
  res->branch_inst_cnt = _branch_inst_cnt();
  res->jump_inst_cnt = _jump_inst_cnt();

  /*
  for(int i=0; i<=7; i++){
    res->cnt[2*i] = *(volatile unsigned int *)((char *)0x60010000+(i<<12));
    res->cnt[2*i+1] = *(volatile unsigned int *)((char *)0x60010008+(i<<12));
  }
  */
}

void bench_done(Result *res) {
  // TODO [COD]
  //  Add postprocess code, record performance counters' current states.
  res->msec = _uptime() - res->msec;

  res->inst_cnt = _inst_cnt() - res->inst_cnt;
  res->mr_cnt = _mr_cnt() - res->mr_cnt;
  res->mw_cnt = _mw_cnt() - res->mw_cnt;
  res->inst_req_delay_cnt = _inst_req_delay_cycle() - res->inst_req_delay_cnt;
  res->inst_delay_cnt = _inst_delay_cycle() - res->inst_delay_cnt;
  res->mr_req_delay_cnt = _mr_req_delay_cycle() - res->mr_req_delay_cnt;
  res->rdw_delay_cnt = _rdw_delay_cycle() - res->rdw_delay_cnt;
  res->mw_req_delay_cnt = _mw_req_delay_cycle() - res->mw_req_delay_cnt;
  res->branch_inst_cnt = _branch_inst_cnt() - res->branch_inst_cnt;
  res->jump_inst_cnt = _jump_inst_cnt() - res->jump_inst_cnt;

  /*
  for(int i=0; i<=7; i++){
    res->cnt[2*i] = *(volatile unsigned int *)((char *)0x60010000+(i<<12)) - res->cnt[2*i];
    res->cnt[2*i+1] = *(volatile unsigned int *)((char *)0x60010008+(i<<12)) - res->cnt[2*i+1];
  }
  */
}

