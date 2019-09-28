import std.stdio;
import std.random : randomShuffle, uniform;
import std.datetime.stopwatch : AutoStart, StopWatch;
import std.datetime;
import dstats.summary;
import core.sys.posix.sys.types;

struct Data
{
	int id;
	double x;
	char[56] payload;
	double y;
	this(int id, double x, double y)
	{
		this.id = id;
		this.x  = x;
		this.y  = y;
	}
}

enum __NR_perf_event_open = 298;

/*
 * Hardware event_id to monitor via a performance monitoring event:
 */
struct perf_event_attr {

	/*
	 * Major type: hardware/software/tracepoint/etc.
	 */
	uint type;

	/*
	 * Size of the attr structure, for fwd/bwd compat.
	 */
	uint size;

	/*
	 * Type specific configuration information.
	 */
	ulong config;

	union {
		ulong sample_period;
		ulong sample_freq;
	}

	ulong sample_type;
	ulong read_format;

	import std.bitmanip : bitfields;

	mixin(bitfields!(
		bool, "disabled",       1, /* off by default        */
		bool, "inherit",        1, /* children inherit it   */
		bool, "pinned",         1, /* must always be on PMU */
		bool, "exclusive",      1, /* only group on PMU     */
		bool, "exclude_user",   1, /* don't count user      */
		bool, "exclude_kernel", 1, /* ditto kernel          */
		bool, "exclude_hv",     1, /* ditto hypervisor      */
		bool, "exclude_idle",   1, /* don't count when idle */
		bool, "mmap",           1, /* include mmap data     */
		bool, "comm",           1, /* include comm data     */
		bool, "freq",           1, /* use freq, not period  */
		bool, "inherit_stat",   1, /* per task counts       */
		bool, "enable_on_exec", 1, /* next exec enables     */
		bool, "task",           1, /* trace fork/exit       */
		bool, "watermark",      1, /* wakeup_watermark      */

		long, "__reserved_1",   49));

	union {
		uint wakeup_events;    /* wakeup every n events */
		uint wakeup_watermark; /* bytes before wakeup   */
	}
	uint  __reserved_2;

	ulong __reserved_3;
}

long perf_event_open(perf_event_attr *hw_event,
				pid_t pid,
				int cpu,
				int group_fd,
				ulong flags)
{
	return syscall(cast(size_t) __NR_perf_event_open, cast(size_t) hw_event, cast(size_t) pid, cast(size_t) cpu, cast(size_t) group_fd, cast(size_t) flags);
}

size_t syscall(size_t ident, size_t n, size_t arg1, size_t arg2, size_t arg3, size_t arg4)
{
	size_t ret;

	synchronized asm @nogc nothrow
	{
		mov RAX, ident;
		mov RDI, n[RBP];
		mov RSI, arg1[RBP];
		mov RDX, arg2[RBP];
		mov R10, arg3[RBP];
		mov R8, arg4[RBP];
		syscall;
		mov ret, RAX;
	}
	return ret;
}

/*
 * attr.type
 */
enum perf_type_id {
	PERF_TYPE_HARDWARE			= 0,
	PERF_TYPE_SOFTWARE			= 1,
	PERF_TYPE_TRACEPOINT			= 2,
	PERF_TYPE_HW_CACHE			= 3,
	PERF_TYPE_RAW				= 4,
	PERF_TYPE_BREAKPOINT			= 5,

	PERF_TYPE_MAX,				/* non-ABI */
}

/*
 * Special "software" events provided by the kernel, even if the hardware
 * does not support performance events. These events measure various
 * physical and sw events of the kernel (and allow the profiling of them as
 * well):
 */
enum perf_sw_ids {
	PERF_COUNT_SW_CPU_CLOCK          = 0,
	PERF_COUNT_SW_TASK_CLOCK         = 1,
	PERF_COUNT_SW_PAGE_FAULTS        = 2,
	PERF_COUNT_SW_CONTEXT_SWITCHES   = 3,
	PERF_COUNT_SW_CPU_MIGRATIONS     = 4,
	PERF_COUNT_SW_PAGE_FAULTS_MIN    = 5,
	PERF_COUNT_SW_PAGE_FAULTS_MAJ    = 6,
	PERF_COUNT_SW_ALIGNMENT_FAULTS   = 7,
	PERF_COUNT_SW_EMULATION_FAULTS   = 8,

	PERF_COUNT_SW_MAX,               /* non-ABI */
}

/*
 * Generalized performance event event_id types, used by the
 * attr.event_id parameter of the sys_perf_event_open()
 * syscall:
 */
enum perf_hw_id {
	/*
	 * Common hardware events, generalized by the kernel:
	 */
	PERF_COUNT_HW_CPU_CYCLES		= 0,
	PERF_COUNT_HW_INSTRUCTIONS		= 1,
	PERF_COUNT_HW_CACHE_REFERENCES		= 2,
	PERF_COUNT_HW_CACHE_MISSES		= 3,
	PERF_COUNT_HW_BRANCH_INSTRUCTIONS	= 4,
	PERF_COUNT_HW_BRANCH_MISSES		= 5,
	PERF_COUNT_HW_BUS_CYCLES		= 6,
	PERF_COUNT_HW_STALLED_CYCLES_FRONTEND	= 7,
	PERF_COUNT_HW_STALLED_CYCLES_BACKEND	= 8,
	PERF_COUNT_HW_REF_CPU_CYCLES		= 9,

	PERF_COUNT_HW_MAX,			/* non-ABI */
}

import core.sys.posix.sys.ioctl;
enum PERF_EVENT_IOC_ENABLE  = _IO(36, 0);
enum PERF_EVENT_IOC_DISABLE = _IO(36, 1);
enum PERF_EVENT_IOC_RESET   = _IO(36, 3);

int main()
{
	import core.stdc.errno : errno;

	enum dataCount = 4_000;
	Data[] data;
	data.reserve(dataCount);
	foreach(i; 0..dataCount)
		data ~= Data(
			i, 
			uniform(-100_000, 100_001),
			uniform(-100_000, 100_001)
		);

	import core.stdc.string;
	perf_event_attr pe_attr_page_faults;
	memset(&pe_attr_page_faults, 0, pe_attr_page_faults.sizeof);
	pe_attr_page_faults.size = pe_attr_page_faults.sizeof;
	pe_attr_page_faults.type =   perf_type_id.PERF_TYPE_HARDWARE;//PERF_TYPE_SOFTWARE;
	pe_attr_page_faults.config = perf_hw_id.PERF_COUNT_HW_CACHE_MISSES;
	// pe_attr_page_faults.config = perf_sw_ids.PERF_COUNT_SW_CONTEXT_SWITCHES;//PERF_COUNT_SW_CPU_CLOCK;//PERF_COUNT_SW_PAGE_FAULTS;
	pe_attr_page_faults.disabled = 1;
	pe_attr_page_faults.exclude_kernel = 1;
	const CPU = -1;
	auto page_faults_fd = cast(int) perf_event_open(&pe_attr_page_faults, 0, CPU, -1, 0);
	if (page_faults_fd == -1) {
		printf("perf_event_open failed for page faults: %s\n", strerror(errno));
		return -1;
	}

	enum runCount = 1;//000;
	Summary total;
	foreach(i; 0..runCount)
	{
		// randomShuffle(data);
		int id0 = -1;
		double d0 = 1e100;
		const before = MonoTime.currTime;
// Start counting
ioctl(page_faults_fd, PERF_EVENT_IOC_RESET, 0);
ioctl(page_faults_fd, PERF_EVENT_IOC_ENABLE, 0);
		{
			foreach(ref e; data)
			{
				const double d = e.x*e.x + e.y*e.y;
				if (d < d0)
				{
					d0 = d;
					id0 = e.id;
				}
			}
		}
import core.sys.posix.unistd;
// Stop counting and read value
ioctl(page_faults_fd, PERF_EVENT_IOC_DISABLE, 0);
ulong page_faults_count;
read(page_faults_fd, &page_faults_count, page_faults_count.sizeof);
		const after = MonoTime.currTime;
		// writeln(id0, " ", d0);

		// total.put((after - before).total!"usecs"/1e6);
		total.put(page_faults_count);
	}
	writeln(total);
	writeln(total.mse);
	return 0;
}
