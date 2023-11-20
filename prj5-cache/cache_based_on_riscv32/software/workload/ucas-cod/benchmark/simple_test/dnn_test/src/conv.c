#include "printf.h"
#include "trap.h"
#include "mul.h"
#include "div.h"
#include "perf_cnt.h"
#include <limits.h>

#define FRAC_BIT 10

#define RD_ADDR 135106448
#define RD_SIZE_D0 1
#define RD_SIZE_D1 1
#define RD_SIZE_D2 28
#define RD_SIZE_D3 28

#define WEIGHT_ADDR 134217728
#define WEIGHT_SIZE_D0 20
#define WEIGHT_SIZE_D1 1
#define WEIGHT_SIZE_D2 5
#define WEIGHT_SIZE_D3 5

#define WR_ADDR 135108240
#define WR_SIZE_D0 1
#define WR_SIZE_D1 20
#define WR_SIZE_D2 12
#define WR_SIZE_D3 12

#define KERN_ATTR_CONV_PAD 0
#define KERN_ATTR_CONV_STRIDE 1
#define KERN_ATTR_POOL_PAD 0
#define KERN_ATTR_POOL_KERN_SIZE 2
#define KERN_ATTR_POOL_STRIDE 2

//MMIO register address of DNN accelerator
#define GPIO_START_ADDR    0x60030000
#define GPIO_DONE_ADDR     0x60030008

struct size_vec4
{
	unsigned d0;
	unsigned d1;
	unsigned d2;
	unsigned d3;
};

struct mem_addr
{
	unsigned rd_addr;
	unsigned weight_addr;
	unsigned wr_addr;
};

int mul(short a, short b)
{
#ifndef USE_MUL
	int ans = mul_ll(a, b);
#else
	int ans = a * b;
#endif
	return ans;
}

struct mem_addr addr = {RD_ADDR, WEIGHT_ADDR, WR_ADDR};
struct size_vec4 rd_size = {RD_SIZE_D0, RD_SIZE_D1, RD_SIZE_D2, RD_SIZE_D3};
struct size_vec4 wr_size = {WR_SIZE_D0, WR_SIZE_D1, WR_SIZE_D2, WR_SIZE_D3};
struct size_vec4 weight_size = {WEIGHT_SIZE_D0, WEIGHT_SIZE_D1, WEIGHT_SIZE_D2, WEIGHT_SIZE_D3};

struct size_vec4 conv_size;

extern char _binary_data_result_bin_start[];
extern char _binary_data_result_bin_size[];

void convolution()
{
	short *in = (short *)addr.rd_addr;
	short *weight = (short *)addr.weight_addr;
	short *out = (short *)addr.wr_addr;

	unsigned output_offset = 0;
	unsigned input_offset = 0;

	unsigned input_fm_w = rd_size.d3;//输入特征图高度
	unsigned input_fm_h = rd_size.d2;//输入特征图宽度

	unsigned pad = KERN_ATTR_CONV_PAD;
	unsigned pad_len = pad << 1;

	unsigned conv_out_w = rd_size.d3 - weight_size.d3 + pad_len;
	unsigned conv_out_h = rd_size.d2 - weight_size.d2 + pad_len;

	unsigned stride = KERN_ATTR_CONV_STRIDE;

	conv_out_w = div(conv_out_w, stride);
	conv_out_h = div(conv_out_h, stride);

	conv_out_w++;
	conv_out_h++;

	conv_size.d0 = wr_size.d0;
	conv_size.d1 = wr_size.d1;//输出特征图通道数
	conv_size.d2 = conv_out_h;//输出特征图高度
	conv_size.d3 = conv_out_w;//输出特征图宽度

	//TODO: Please add your implementation here

	int filter_size = mul(WEIGHT_SIZE_D2, WEIGHT_SIZE_D3) + 1;//卷积核大小

	short (*input_vector)[WEIGHT_SIZE_D1][input_fm_h][input_fm_w];//输入图像地址
	short (*output_vector)[WEIGHT_SIZE_D0][conv_out_h][conv_out_w];//输出图像地址
	short (*filter)[WEIGHT_SIZE_D0][WEIGHT_SIZE_D1][filter_size];//卷积核地址

	input_vector  	= (void*)(in + input_offset);
	output_vector 	= (void*)(out + output_offset);
	filter 		= (void*)weight;//转化为void*才能赋值

	for(int no = 0;no < WEIGHT_SIZE_D0;no++){
		for(int ni = 0;ni < WEIGHT_SIZE_D1;ni++){
			for(int y = 0;y < conv_out_h;y++){
				for(int x = 0;x < conv_out_w;x++){
					if(ni == 0){
						(*output_vector)[no][y][x] = (*filter)[no][0][0]; //filter[i][0][0]存储第i个通道的bias值
					}
					
					int raw_data = 0;//用32位int类型存储中间计算结果
					for(int ky = 0;ky < WEIGHT_SIZE_D2;ky++){
						for(int kx = 0;kx < WEIGHT_SIZE_D3;kx++){
							int current_x = mul(x, stride) - pad + kx;//当前输入的访问x坐标(宽度)
							int current_y = mul(y, stride) - pad + ky;//当前输入的访问y坐标(高度)

							if(current_x >= 0 && current_x < input_fm_w && current_y >= 0 && current_y < input_fm_h){ //若输入的当前访问像素是padding，则结果加0，直接跳过
								raw_data += mul(
									(*input_vector)[ni][current_y][current_x], 
									(*filter)[no][ni][mul(ky, WEIGHT_SIZE_D3) + kx + 1]
								);//用32位int类型存储中间计算结果
							}
						}
					}
					(*output_vector)[no][y][x] += raw_data >> FRAC_BIT;//由于用整数运算代替小数，所以最终结果需要移位
				}
			}
		}
	}
}

void pooling()
{
	short *out = (short *)addr.wr_addr;

	unsigned output_offset = 0;
	unsigned input_offset = 0;

	unsigned input_fm_w = conv_size.d3;//卷积操作输出特征图宽度
	unsigned input_fm_h = conv_size.d2;//卷积操作输出特征图高度

	unsigned pad = KERN_ATTR_POOL_PAD;
	unsigned pad_len = pad << 1;

	unsigned pad_w_test = conv_size.d3 - KERN_ATTR_POOL_KERN_SIZE;
	unsigned pad_h_test = conv_size.d2 - KERN_ATTR_POOL_KERN_SIZE;

	unsigned pool_out_w = pad_w_test + pad_len;
	unsigned pool_out_h = pad_h_test + pad_len;

	unsigned stride = KERN_ATTR_POOL_STRIDE;

	unsigned pad_w_test_remain = pad_w_test - mul(div(pad_w_test, stride), stride);
	unsigned pad_h_test_remain = pad_h_test - mul(div(pad_h_test, stride), stride);

	pool_out_w = div(pool_out_w, stride);
	pool_out_h = div(pool_out_h, stride);
	pool_out_w++; //池化操作输出特征图宽度
	pool_out_h++; //池化操作输出特征图高度

	if ((!pad) && (pad_w_test_remain || pad_h_test_remain))
	{
		pool_out_w++;
		pool_out_h++;
	}

	//TODO: Please add your implementation here

	unsigned long temp_pool_store_offset = mul(WEIGHT_SIZE_D0, mul(input_fm_h, input_fm_w));//池化前数据的总大小

	short (*before_pool_vector)[WEIGHT_SIZE_D0][input_fm_h][input_fm_w];//池化前的数据存储地址
	short (*after_pool_vector)[WEIGHT_SIZE_D0][pool_out_h][pool_out_w];//池化后的数据临时存储地址(存储在池化前数据后面，不开新的空间)

	before_pool_vector = (void*)(out + input_offset);
	after_pool_vector = (void*)(out + input_offset + temp_pool_store_offset);//转化为void*才能赋值

	for(int no = 0;no < WEIGHT_SIZE_D0;no++){
		for(int y = 0;y < pool_out_h;y++){
			for(int x = 0;x < pool_out_w;x++){
				short max = SHRT_MIN;//初始值为short类型最小值

				for(int ky = 0;ky < KERN_ATTR_POOL_KERN_SIZE;ky++){
					for(int kx = 0;kx < KERN_ATTR_POOL_KERN_SIZE;kx++){
						int current_x = mul(x, stride) - pad + kx; //当前输入的访问x坐标(宽度)
						int current_y = mul(y, stride) - pad + ky; //当前输入的访问y坐标(高度)

						if(current_x >= 0 && current_x < input_fm_w && current_y >= 0 && current_y < input_fm_h){//若输入的当前访问像素不是padding,跳过
							if(max < (*before_pool_vector)[no][current_y][current_x]){
								max = (*before_pool_vector)[no][current_y][current_x];//最大值更新
							}
						}
					}
				}
				(*after_pool_vector)[no][y][x] = max;
			}
		}
	}

	//搬运池化结果
	short* temp_address = out + (input_offset + temp_pool_store_offset);//临时数据储存的地址
	short* output_address = out + output_offset;//结果输出的地址

	int total_num = mul(WEIGHT_SIZE_D0, mul(pool_out_h, pool_out_w));

	for(int i = 0; i < total_num; i++, temp_address++, output_address++){
		*output_address = *temp_address;
	}
}

#ifdef USE_HW_ACCEL
void launch_hw_accel()
{
	volatile int* gpio_start = (void*)(GPIO_START_ADDR);
	volatile int* gpio_done = (void*)(GPIO_DONE_ADDR);

	//TODO: Please add your implementation here

	(*gpio_start) |= 0x1;//START第0位写1代表加速器启动
	while(!((*gpio_done) & 0x1));//根据DONE第0位，检测是否以及完成卷积操作
	(*gpio_start) &= 0x0;//还原START
}
#endif

int comparing()
{
	char *out = (char *)addr.wr_addr;
	char *result = (char *)_binary_data_result_bin_start;

#ifdef USE_HW_ACCEL
	int count = (int)_binary_data_result_bin_size + 
		    (16 - WR_SIZE_D3) * 2 * WR_SIZE_D2 * WR_SIZE_D1;
#else
	int count = (int)_binary_data_result_bin_size;
#endif

	for (int i = 0, j = 0; i < count; i++)
	{
#ifdef USE_HW_ACCEL
		int alignment = i & 0x0000001f;
		if (alignment >= (WR_SIZE_D3 << 1))
			continue;
#endif
		if (*(out + i) != *(result + j))
		{
			printf("Failed! at address %x and %x with data %x and %x\n", out + i, result + j, *(out + i), *(result + j));
			return 1;
		}
		j++;
	}

	printf("Passed!\n");
	return 0;
}

int main()
{
	Result res;
	bench_prepare(&res);

#ifdef USE_HW_ACCEL
	printf("Launching task...\n");
	launch_hw_accel();
#else
	printf("starting convolution\n");
	convolution();
	printf("starting pooling\n");
	pooling();
#endif

	int result = comparing();

	bench_done(&res);

	unsigned long high_cycle = res.msec >> 32;
	unsigned long low_cycle  = res.msec & 0xffffffff; 

	printf("==============Hardware Performance Counter Result==============\n");
	if(high_cycle){
		printf("\tCycles: at least %u%u\n", high_cycle, low_cycle);
	}
	else{
		printf("\tCycles: at least %u\n", low_cycle);
	}//周期计数器可能会溢出

	printf("\tInstruction Count: at least %u\n", res.inst_cnt);
	printf("\tMemory Read Instruction Count: at least %u\n", res.mr_cnt);
	printf("\tMemory Write Instruction Count: at least %u\n", res.mw_cnt);
	printf("\tInstruction Fetch Request Delay Cycle: at least %u\n", res.inst_req_delay_cnt);
	printf("\tInstruction Fetch Delay Cycles: at least %u\n", res.inst_delay_cnt);
	printf("\tMemory Read Request Delay Cycles: at least %u\n", res.mr_req_delay_cnt);
	printf("\tRead Data Delay Cycles: at least %u\n", res.rdw_delay_cnt);
	printf("\tMemory Write Request Delay Cycles: at least %u\n", res.mw_req_delay_cnt);
	printf("\tBranch Instruction Count: at least %u\n", res.branch_inst_cnt);
	printf("\tJump Instruction Count: at least %u\n", res.jump_inst_cnt);
	printf("==============================================================\n");


	printf("benchmark finished\n");

	if (result == 0) {
		hit_good_trap();
	} else {
		nemu_assert(0);
	}

	return 0;
}
