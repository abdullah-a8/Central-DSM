CC       = gcc
LINKER   = gcc
AR       = ar

# change these to proper directories where each file should be
SRCDIR   = src
INCDIR   = src
BUILDDIR = build
OBJDIR   = $(BUILDDIR)/obj
LIBDIR   = $(BUILDDIR)/lib
TESTDIR  = $(BUILDDIR)/tests
BINDIR   = $(BUILDDIR)/bin

LIB_NAME = centraldsm

# compiling flags here
CFLAGS   = -Wall -Wextra -Wno-unused-parameter -std=c99 -fPIC -D_GNU_SOURCE
# linking flags here
LFLAGS   = -std=c99 -I$(INCDIR) -L$(LIBDIR) -lpthread
ARFLAGS  = -cvq
SOFLAGS  = -shared -Wl,-soname,lib$(LIB_NAME).so

# TSan flags
TSAN_CFLAGS = -fsanitize=thread -g -O1
TSAN_LFLAGS = -fsanitize=thread

# Valgrind flags
VALGRIND_FLAGS = --leak-check=full --show-leak-kinds=all --track-origins=yes --verbose

TEST1_NAME = test_dsm_init_master
TEST2_NAME = test_dsm_init_slave
TEST3_NAME = test_dsm_lock_write
TEST4_NAME = test_dsm_lock_read
TEST5_NAME = test_dsm_lock_read2

DEMO1_NAME = demo_master_writer
DEMO2_NAME = demo_slave_writer_reader
DEMO3_NAME = demo_slave_reader

SOURCES  := $(wildcard $(SRCDIR)/*.c)
INCLUDES := $(wildcard $(INCDIR)/*.h)
OBJECTS  := $(SOURCES:$(SRCDIR)/%.c=$(OBJDIR)/%.o)
RM        = rm -rf
MKDIR_P   = mkdir -p

all: out_directories lib tests demo

$(OBJECTS): $(OBJDIR)/%.o : $(SRCDIR)/%.c
	$(CC) $(CFLAGS) -I$(INCDIR) -c $< -o $@

.PHONY: lib
lib: out_directories libstatic libdynamic

.PHONY: libstatic
libstatic: out_directories $(LIBDIR)/lib$(LIB_NAME).a

.PHONY: libdynamic
libdynamic: out_directories $(LIBDIR)/lib$(LIB_NAME).so

$(LIBDIR)/lib$(LIB_NAME).a: $(OBJDIR)/binn.o $(OBJDIR)/dsm_socket.o $(OBJDIR)/dsm_protocol.o $(OBJDIR)/dsm_memory.o $(OBJDIR)/dsm_master.o $(OBJDIR)/dsm.o $(OBJDIR)/list.o $(OBJDIR)/dsm_core.o
	$(AR) $(ARFLAGS) $@ $^

$(LIBDIR)/lib$(LIB_NAME).so: $(OBJDIR)/binn.o $(OBJDIR)/dsm_socket.o $(OBJDIR)/dsm_protocol.o $(OBJDIR)/dsm_memory.o $(OBJDIR)/dsm_master.o $(OBJDIR)/dsm.o $(OBJDIR)/list.o $(OBJDIR)/dsm_core.o
	$(LINKER) $(SOFLAGS) -o $@ $^

.PHONY: tests
tests: out_directories libstatic $(TESTDIR)/$(TEST1_NAME) $(TESTDIR)/$(TEST2_NAME) $(TESTDIR)/$(TEST3_NAME) $(TESTDIR)/$(TEST4_NAME) $(TESTDIR)/$(TEST5_NAME)

.PHONY: demo
demo: out_directories libstatic $(TESTDIR)/$(DEMO1_NAME) $(TESTDIR)/$(DEMO2_NAME) $(TESTDIR)/$(DEMO3_NAME)

$(TESTDIR)/$(TEST1_NAME): $(SRCDIR)/test_dsm_init_master.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

$(TESTDIR)/$(TEST2_NAME): $(SRCDIR)/test_dsm_init_slave.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

$(TESTDIR)/$(TEST3_NAME): $(SRCDIR)/test_dsm_lock_write.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

$(TESTDIR)/$(TEST4_NAME): $(SRCDIR)/test_dsm_lock_read.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

$(TESTDIR)/$(TEST5_NAME): $(SRCDIR)/test_dsm_lock_read2.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a


$(TESTDIR)/$(DEMO1_NAME): $(SRCDIR)/demo_master_writer.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

$(TESTDIR)/$(DEMO2_NAME): $(SRCDIR)/demo_slave_writer_reader.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

$(TESTDIR)/$(DEMO3_NAME): $(SRCDIR)/demo_slave_reader.c
	$(LINKER) -o $@ $(LFLAGS) $^ $(LIBDIR)/lib$(LIB_NAME).a

.PHONY: out_directories
out_directories:
	@$(MKDIR_P) $(OBJDIR) $(TESTDIR) $(LIBDIR) $(BINDIR)

.PHONY: clean
clean:
	@$(RM) $(BUILDDIR)

.PHONY: remove
remove: clean

# TSan builds
.PHONY: tsan
tsan: out_directories lib-tsan tests-tsan demo-tsan

.PHONY: lib-tsan
lib-tsan: $(LIBDIR)/lib$(LIB_NAME)_tsan.a

$(LIBDIR)/lib$(LIB_NAME)_tsan.a: $(OBJDIR)/binn_tsan.o $(OBJDIR)/dsm_socket_tsan.o $(OBJDIR)/dsm_protocol_tsan.o $(OBJDIR)/dsm_memory_tsan.o $(OBJDIR)/dsm_master_tsan.o $(OBJDIR)/dsm_tsan.o $(OBJDIR)/list_tsan.o $(OBJDIR)/dsm_core_tsan.o
	$(AR) $(ARFLAGS) $@ $^

$(OBJDIR)/%_tsan.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) $(TSAN_CFLAGS) -I$(INCDIR) -c $< -o $@

.PHONY: tests-tsan
tests-tsan: $(TESTDIR)/$(TEST1_NAME)_tsan $(TESTDIR)/$(TEST2_NAME)_tsan $(TESTDIR)/$(TEST3_NAME)_tsan $(TESTDIR)/$(TEST4_NAME)_tsan $(TESTDIR)/$(TEST5_NAME)_tsan

.PHONY: demo-tsan
demo-tsan: $(TESTDIR)/$(DEMO1_NAME)_tsan $(TESTDIR)/$(DEMO2_NAME)_tsan $(TESTDIR)/$(DEMO3_NAME)_tsan

$(TESTDIR)/%_tsan: $(SRCDIR)/%.c $(LIBDIR)/lib$(LIB_NAME)_tsan.a
	$(LINKER) -o $@ $(LFLAGS) $(TSAN_LFLAGS) $< $(LIBDIR)/lib$(LIB_NAME)_tsan.a

# Valgrind test runner
.PHONY: valgrind
valgrind: tests demo
	@echo "Running Valgrind tests..."
	@echo "Note: Run individual tests with: make valgrind-test1, valgrind-test2, etc."

.PHONY: valgrind-test1
valgrind-test1: $(TESTDIR)/$(TEST1_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(TEST1_NAME).log $(TESTDIR)/$(TEST1_NAME)

.PHONY: valgrind-test2
valgrind-test2: $(TESTDIR)/$(TEST2_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(TEST2_NAME).log $(TESTDIR)/$(TEST2_NAME)

.PHONY: valgrind-test3
valgrind-test3: $(TESTDIR)/$(TEST3_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(TEST3_NAME).log $(TESTDIR)/$(TEST3_NAME)

.PHONY: valgrind-test4
valgrind-test4: $(TESTDIR)/$(TEST4_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(TEST4_NAME).log $(TESTDIR)/$(TEST4_NAME)

.PHONY: valgrind-test5
valgrind-test5: $(TESTDIR)/$(TEST5_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(TEST5_NAME).log $(TESTDIR)/$(TEST5_NAME)

.PHONY: valgrind-demo1
valgrind-demo1: $(TESTDIR)/$(DEMO1_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(DEMO1_NAME).log $(TESTDIR)/$(DEMO1_NAME)

.PHONY: valgrind-demo2
valgrind-demo2: $(TESTDIR)/$(DEMO2_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(DEMO2_NAME).log $(TESTDIR)/$(DEMO2_NAME)

.PHONY: valgrind-demo3
valgrind-demo3: $(TESTDIR)/$(DEMO3_NAME)
	valgrind $(VALGRIND_FLAGS) --log-file=$(BUILDDIR)/valgrind-$(DEMO3_NAME).log $(TESTDIR)/$(DEMO3_NAME)

# Help target
.PHONY: help
help:
	@echo "CentralDSM Makefile Targets:"
	@echo "  make              - Build all libraries, tests, and demos"
	@echo "  make lib          - Build static and dynamic libraries"
	@echo "  make tests        - Build test programs"
	@echo "  make demo         - Build demo programs"
	@echo "  make clean        - Remove all build artifacts"
	@echo ""
	@echo "Thread Sanitizer (TSan) targets:"
	@echo "  make tsan         - Build everything with TSan instrumentation"
	@echo "  make lib-tsan     - Build library with TSan"
	@echo "  make tests-tsan   - Build tests with TSan"
	@echo "  make demo-tsan    - Build demos with TSan"
	@echo ""
	@echo "Valgrind targets:"
	@echo "  make valgrind-test1  - Run test1 under Valgrind"
	@echo "  make valgrind-test2  - Run test2 under Valgrind"
	@echo "  make valgrind-test3  - Run test3 under Valgrind"
	@echo "  make valgrind-test4  - Run test4 under Valgrind"
	@echo "  make valgrind-test5  - Run test5 under Valgrind"
	@echo "  make valgrind-demo1  - Run demo1 under Valgrind"
	@echo "  make valgrind-demo2  - Run demo2 under Valgrind"
	@echo "  make valgrind-demo3  - Run demo3 under Valgrind"
	@echo ""
	@echo "Output directory: $(BUILDDIR)/"