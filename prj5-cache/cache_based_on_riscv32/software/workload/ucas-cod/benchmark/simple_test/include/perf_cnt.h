
#ifndef __PERF_CNT__
#define __PERF_CNT__

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Result {
	int pass;
	unsigned long long msec;

	unsigned long inst_cnt;
	unsigned long mr_cnt;
	unsigned long mw_cnt;
	unsigned long inst_req_delay_cnt;
	unsigned long inst_delay_cnt;
	unsigned long mr_req_delay_cnt;
	unsigned long rdw_delay_cnt;
	unsigned long mw_req_delay_cnt;
	unsigned long branch_inst_cnt;
	unsigned long jump_inst_cnt;

	/*
	unsigned long cnt[15]
	*/

} Result;

void bench_prepare(Result *res);
void bench_done(Result *res);

#endif
