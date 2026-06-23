' CmpBasic.bas - creates a windows 64 executable file byte by byte with simple BASIC ability

' BASIC commands supported:

' Suffix-less variables are supported, and implicitly typed dynamic strings are permitted
' Variable names have a 64 character limit
' Add GRAPHICS at the beginning for a graphics window (640 x 480 default)
' PSET to draw a single dot to the framebuffer - PSET X, Y, color

' The compiler itself is a polling-based batch processor, and the graphical executable programs it generates are event-driven

' NOTE: TYPING MECHANICS & THE FRONTEND ENFORCER
' At the core memory-resolution level, the backend uses duck typing
' (Top-Down Implicit Typing / RHS Lookahead) to resolve suffix-less variables.
' The compiler embraces modern QB64-style tolerance: if a suffix-less variable
' is assigned a string (e.g., myVar = "Hello"), the RHS lookahead implicitly
' types it as a dynamic string seamlessly. However, the frontend (refineCode)
' still acts as an "Enforcer" for explicit declarations. Unless the #CLASSIC
' directive is active, refineCode polices and formats explicitly declared
' string namespaces (like DSTRING) to ensure structural consistency.
'
' NOTE: STRING DECLARATIONS (DSTRING vs STRING) AND #STRINGSTRICT
' While duck typing handles implicit strings cleanly, explicit declarations are managed
' based on the #STRINGSTRICT directive:
' When #STRINGSTRICT is active, strict separation is enforced:
'  - DSTRING : Explicit dynamic string. Automatically appends and enforces a $
'              suffix under the hood via the frontend enforcer. Cannot have a * length.
'  - STRING  : Fixed-length string. Requires a * and a numeric length. Permanently
'              preserves whatever suffix state ($ or no $) was used at declaration.
' When #STRINGSTRICT is not active, the compiler behaves like standard QB64:
'  - STRING  : Can act as a dynamic string (AS STRING) or fixed-length (AS STRING * len).
'  - DSTRING : Always acts as a dynamic string and cannot have a * length.
' Strings implicitly defined on the fly will always default to dynamic.
'
' To prevent malformed declarations (e.g., DIM var AS STRING * @#$) from corrupting
' variable tracking on subsequent lines, refineCode uses a "Suspension" state machine.
' It will isolate and ignore the invalid variable until the declaration is fixed.

' NOTE: TIRA (THREE-ADDRESS CODE) NAMESPACE PREFIXES
' The TIRA intermediate representation relies on a strict prefix system to define
' the nature of variables and labels during the compilation phase:
'  ! (exclamation) : Global compiler/parser state variables (e.g., !GFX_CUR_X)
'  ~ (tilde)       : Ephemeral, localized TIRA scratchpad variables (e.g., ~T_0)
'                    These are strictly internal and dynamically typed/allocated.
'  @ (at)          : Addresses and compiler-generated Jump Labels (e.g., @MY_LOOP_START)
'                    Established by the parser to signify a memory address or location
'  % (percent)     : User-defined Labels (e.g., %10, %MY_LABEL).
'                    Automatically applied to isolate custom code target locations
' # (Hash) : Absolute symbol index reference (e.g., #42).
' Bypasses scope resolution to directly target a specific variable by its ID

' NOTE: SUBROUTINE AND FUNCTION ARGUMENT PASSING
' Unlike traditional QBasic which passes variables by reference by default, this
' compiler strictly enforces pass-by-value behavior for all standard variables
' similar to C++. When a variable is passed into a sub or function, a completely
' disconnected clone of that data is handed to the local scope. Any modifications
' made to the argument inside the subroutine will not reflect back in the caller
' scope. To retrieve modified data, functions must explicitly return a value
' Arrays serve as a structural exception to this pass-by-value rule
' When an array is passed, its underlying heap memory address is assigned
' to the target variable along with its corresponding bounds tracking
' Because both scopes point to the same memory location, modifications made
' to array elements inside the subroutine will reflect in the caller scope

' NOTE: LEFT-SIDE IMPLICIT ASSUMPTION
' The compiler allows implicit variable creation on the left side of
' an assignment because it is processed first using the symbol resolver
' However, variables on the right side of the assignment explicitly
' disable implicit resolution to prevent compiling undefined variables

' NOTE: TIRA AND THE INTELLIGENT MACRO-ASSEMBLER
' The compiler intermediate representation (TIRA) operates as a hybrid
' intelligent macro-assembler rather than a strictly typed IR
' The frontend stream-based parsers handle structural evaluation, operator precedence,
' and scope resolution without worrying about hardware-level type casting
' When TIRA commands are queued, the backend tasm_ suite acts as an intelligent
' agent to evaluate the symbol table and dynamically inject the correct x64
' hardware coercion instructions to resolve type mismatches natively
' This decoupling prevents redundant casting loops and keeps the frontend clean

' NOTE: X64 ABI COMPLIANCE AND STACK FRAMES
'
' The backend strictly adheres to the Windows x64 calling convention using
' stable RBP frame pointers to anchor the local execution scope
' When TC_ABI_PROLOGUE executes, the four volatile parameter registers
' (RCX, RDX, R8, R9) are safely spilled into the 32-byte shadow space
' provided by the caller
' TC_ABI_READ_ARG leverages this stable RBP anchor to retrieve all arguments
' sequentially from the stack, immunizing parameter retrieval against
' runtime RSP shifts or register clobbering
' Furthermore, TC_CALL universally guarantees a compliant 32-byte
' shadow space allocation for all function calls, internal or external
'
' NOTE: TIRA GLOBAL VARIABLE NAMING CONVENTION (THE HYBRID MODEL)
'
' THIS TRANSITION IS IN PROCESS - THIS IS NOT FOR USER GLOBALS, ONLY COMPILER GLOBALS
'
' To prevent variable collisions and maintain strict hardware-level context
' across the TIRA backend, all global persistent variables generated by the
' compiler must adhere to a strict all-uppercase naming convention. We are
' transitioning to prefix global variables with !G_ to clearly separate them
' from local or ephemeral definitions.
'
' Format: !G_[SUBSYSTEM]_[NAME]_[ROLE]
'
' The [SUBSYSTEM] prefix indicates where the variable belongs:
'  - !G_SYS_    : Core compiler mechanics and critical state
'  - !G_MEM_    : Heap allocation and memory tracking
'  - !G_GFX_    : Graphical framebuffer and rendering state
'  - !G_IO_     : Input/Output operations and buffers
'  - !G_MATH_   : Accumulators for complex intrinsic math operations
'  - !G_EVAL_   : Permanent storage for Shunting Yard intrinsic evaluations.
'                 (When intrinsic functions are evaluated/migrated, the word HOIST
'                 is explicitly integrated here, e.g., !G_EVAL_HOIST_ASC_...)
'  - !G_WND_    : Thread-safe variables for the Windows Message Loop
'  - !G_LAYOUT_ : Hardcoded base pointers mapped directly to the data segment
'
' The [ROLE] suffix dictates exactly how the variable is allowed to be used:
'  - _PTR   : A 64-bit memory address (used strictly with TC_READ_MEM / TC_WRITE_MEM)
'  - _IDX   : An array index, offset multiplier, or tracking counter
'  - _VAL   : A raw scalar numeric value
'  - _DESC$ : A 24-byte String Descriptor containing a pointer, length, and flag
'  - _FLAG  : A boolean state, spinlock, or toggle
'  - _ARR   : A fixed block of memory allocated as an array in the data segment
'
' NOTE: AVOIDANCE OF LEGACY TYPE SUFFIXES ON TIRA VARIABLES
' Internal TIRA variables strictly avoid using legacy QB-style type suffixes
' (such as #, !, %, &) at the end of their names to keep the [ROLE] suffixes pristine
' If an internal variable requires a specific hardware type (such as TYPE_DOUBLE),
' the compiler resolves the clean name and explicitly overrides the .DataType property
' in the symbol table immediately afterward
' Strings (_DESC$) remain the sole exception, as the standard string signifier
' is intentionally integrated directly into the role designation

CONST SCREENSIZEX = 640
CONST SCREENSIZEY = 360

'''' Visual setup
SCREEN _NEWIMAGE(SCREENSIZEX, SCREENSIZEY, 13), 1, 0
_FULLSCREEN '_SQUAREPIXELS
_FONT 8

CONST palRED = 0
CONST palGREEN = 1
CONST palBLUE = 2

CONST TOP = 0
CONST MIDDLE = 1
CONST BOTTOM = 2

CONST IMPLICIT_FAIL = 0
CONST IMPLICIT_SUCCESS = 1
CONST IMPLICIT_NOT_ASSIGN = 2

CONST ASIS = 0 ' For throwCompilerError
CONST WITHFAILED = 1

CONST TIRA_OP_SAFETY = 1 ' When active, only TIRA and setup can use opcodes

CONST USE_DIB_SECTION = 0 ' Use hardware acceleration in output.exe

CONST EDITOR_LINE_MAX = 65536 ' 1-based array tracking is used for code editor lines. This is not the case for the status bar
CONST COMPILE_LINE_MAX = EDITOR_LINE_MAX * 4 'A multiple to safely accommodate flattened code expansion, editorLineLinkMap to link flattened lines to the original editor string array

CONST STACKSAFETYCHECK = 1

CONST UI_FLASH_TIME = 0.1

CONST ALIM = 1 ' Allow Implicit

CONST DEFAULT = 0

CONST LOCAL_GLOBAL = 0
CONST LOCAL_STANDARD = 1
CONST LOCAL_ABSOLUTE = 2

CONST EDITOR_BOX_X = 49
CONST RIGHT_BOX_X = 518
CONST LEFT_SPACING = 5 ' Gap between the white line on the box border and the left of the text in the editor and status bar
CONST RIGHT_BOX_SPACING = 5 ' Left text gap for the right side function list box

' Ratio-based limits scaling dynamically based on line count
CONST MAX_TOKENS = 128
CONST MAX_PATCHES = EDITOR_LINE_MAX * 8
CONST MAX_LABELS = EDITOR_LINE_MAX \ 4 ' Labels have been integrated into the hash system, but this is needed for the patch ratios below
CONST MAX_GOTO_PATCHES = MAX_LABELS
CONST MAX_IAT_PATCHES = MAX_PATCHES
CONST MAX_CTRLS = EDITOR_LINE_MAX \ 16
CONST MAX_CALL_PATCHES = MAX_LABELS
CONST MAX_SUBS = EDITOR_LINE_MAX \ 64
CONST MAX_SYMBOLS = EDITOR_LINE_MAX * 4
CONST MAX_TEXT_CONSTS = EDITOR_LINE_MAX \ 2
CONST MAX_RT_PATCHES = MAX_PATCHES
CONST MAX_UI_SUBS = MAX_SUBS
CONST MAX_RT_ROUTINES = 128

CONST MAX_TIRA_LINES = EDITOR_LINE_MAX * 16

' Internal compiler commands use !, do not use _

' Tokenizer encodes tokens as strings in the lineTokens$() array
' Keywords get a two-byte encoding: high byte is kwVal\256, low byte is kwVal AND 255
' Keyword values start at 512
' Operators and symbols get a two-byte encoding: high byte is 1, low byte is the ASCII value
' Identifiers (variable names) are stored as plain strings
' Numeric literals are stored as plain strings (e.g. "42" or "-7")
' retTokenVal decodes a token: returns the two-byte value if high byte < 32, else returns 0
' A return of 0 from retTokenVal means the token is a plain string (identifier or number)

'''' Token constants

CONST TOK_AND = 512
CONST TOK_ANY = 513
CONST TOK_AS = 514
CONST TOK_ASC = 515
CONST TOK_ATN = 516
CONST TOK_BEEP = 517
CONST TOK_BYTE = 518
CONST TOK_CALL = 519
CONST TOK_CASE = 520
CONST TOK_CHR = 521
CONST TOK_CLASSIC = 522
CONST TOK_CLS = 523
CONST TOK_COLOR = 524
CONST TOK_COMMON = 525
CONST TOK_DECLARE = 526
CONST TOK_DEF = 527
CONST TOK_DEFINT = 528
CONST TOK_DIM = 529
CONST TOK_DO = 530
CONST TOK_DOUBLE = 531
CONST TOK_DSTRING = 532 ' Dynamic string
CONST TOK_ELSE = 533
CONST TOK_END = 534
CONST TOK_ERROR = 535
CONST TOK_EXIT = 536
CONST TOK_FONT = 537
CONST TOK_FOR = 538
CONST TOK_FULLSCREEN = 539
CONST TOK_FUNCTION = 540
CONST TOK_GDOUBLE = 541
CONST TOK_GLOBAL = 542
CONST TOK_GOTO = 543
CONST TOK_GRAPHICS = 544
CONST TOK_IF = 545
CONST TOK_INKEY = 546
CONST TOK_INKEYF = 547
CONST TOK_INPUT = 548
CONST TOK_INT = 549
CONST TOK_INTEGER = 550
CONST TOK_INTEGER64 = 551
CONST TOK_KEYDOWN = 552
CONST TOK_LEFT = 553
CONST TOK_LEN = 554
CONST TOK_LET = 555
CONST TOK_LINE = 556
CONST TOK_LOCATE = 557
CONST TOK_LONG = 558
CONST TOK_LOOP = 559
CONST TOK_LTRIM = 560
CONST TOK_MID = 561
CONST TOK_NEXT = 562
CONST TOK_NOT = 563
CONST TOK_ON = 564
CONST TOK_OR = 565
CONST TOK_PRINT = 566
CONST TOK_PSET = 567
CONST TOK_RESUME = 568
CONST TOK_RETURN = 569
CONST TOK_RIGHT = 570
CONST TOK_RTRIM = 571
CONST TOK_SCREEN = 572
CONST TOK_SELECT = 573
CONST TOK_SHARED = 574
CONST TOK_SINGLE = 575
CONST TOK_STEP = 576
CONST TOK_STR = 577
CONST TOK_STRING = 578
CONST TOK_SUB = 579
CONST TOK_THEN = 580
CONST TOK_TO = 581
CONST TOK_TYPE = 582
CONST TOK_UCASE = 583
CONST TOK_UNSIGNED = 584
CONST TOK_UNTIL = 585
CONST TOK_VAL = 586

' Newer commands

CONST TOK_CINT = 587
CONST TOK_CLNG = 588
CONST TOK_CSNG = 589
CONST TOK_CDBL = 590
CONST TOK_HEX = 591
CONST TOK_SPACE = 592
CONST TOK_DEFINT_NORM = 593
CONST TOK_POKE = 594 ' Implemented as an ignored command
CONST TOK_PEEK = 595 ' Implemented as an ignored command
CONST TOK_GOSUB = 596
CONST TOK_STRINGSTRICT = 597
CONST TOK_GET = 598
CONST TOK_PUT = 599
CONST TOK_DISPLAY = 600 ' Implemented as an ignored command
CONST TOK_LIMIT = 601 ' Implemented as an ignored command
CONST TOK_OPEN = 602
CONST TOK_CLOSE = 603
CONST TOK_BINARY = 604
CONST TOK_RANDOM = 605
CONST TOK_LOF = 606
CONST TOK_KILL = 607
CONST TOK_DISPLAYI = 608 ' Display, but set a flag so printed text can be seen right away
CONST TOK_POINT = 609
CONST TOK_PALETTECOLOR = 610
CONST TOK_RGB32 = 611
CONST TOK_STOP = 612
CONST TOK_SIN = 613
CONST TOK_COS = 614
CONST TOK_CIRCLE = 615
CONST TOK_RANDOMIZE = 616
CONST TOK_TIMER = 617
CONST TOK_TIMER = 617
CONST TOK_WHILE = 618
CONST TOK_WEND = 619
CONST TOK_DATA = 620
CONST TOK_READ = 621
CONST TOK_RESTORE = 622
CONST TOK_PALETTE = 623
CONST TOK_EMERALD = 624 ' Allows := for assigns and sets STRINGSTRICT
CONST TOK_REM = 625
CONST TOK_STATIC = 626
CONST TOK_DYNAMIC = 627
CONST TOK_REDIM = 628
CONST TOK_MOUSEINPUT = 629
CONST TOK_MOUSEX = 630
CONST TOK_MOUSEY = 631
CONST TOK_MOUSEBUTTON = 632
CONST TOK_MOUSEWHEEL = 633


'''' Shunting Yard Operator Constants
CONST TOK_OP_LPAREN = 296 ' 256 + ASC("(")
CONST TOK_OP_RPAREN = 297 ' 256 + ASC(")")
CONST TOK_OP_MUL = 298 ' 256 + ASC("*")
CONST TOK_OP_PLUS = 299 ' 256 + ASC("+")
CONST TOK_OP_MINUS = 301 ' 256 + ASC("-")
CONST TOK_OP_DIV = 303 ' 256 + ASC("/")
CONST TOK_OP_LESS = 316 ' 256 + ASC("<")
CONST TOK_OP_EQUAL = 317 ' 256 + ASC("=")
CONST TOK_OP_GREATER = 318 ' 256 + ASC(">")
CONST TOK_OP_IDIV = 348 ' 256 + ASC("\")
CONST TOK_OP_POW = 350 ' 256 + ASC("^")
CONST TOK_OP_LESS_EQUAL = 1000
CONST TOK_OP_GREATER_EQUAL = 1001
CONST TOK_OP_NOT_EQUAL = 1002
CONST TOK_OP_UNARY_MINUS = 1003
CONST TOK_OP_UNARY_NOT = 1004

CONST SHUNT_FUNC = 2000
CONST SHUNT_ARRAY = 2001
CONST SHUNT_CAST = 2002

CONST IAT_INVALID = 0 ' The Import Address Table functions as a dedicated jump directory located in the .idata section of output.exe
CONST IAT_GETSTDHANDLE = 1
CONST IAT_WRITEFILE = 2
CONST IAT_READFILE = 3
CONST IAT_EXITPROCESS = 4
CONST IAT_GETMODULEHANDLEA = 5
CONST IAT_SETCONSOLEMODE = 6
CONST IAT_DEFWINDOWPROCA = 7
CONST IAT_REGISTERCLASSEXA = 8
CONST IAT_CREATEWINDOWEXA = 9
CONST IAT_SHOWWINDOW = 10
CONST IAT_PEEKMESSAGEA = 11
CONST IAT_TRANSLATEMESSAGE = 12
CONST IAT_DISPATCHMESSAGEA = 13
CONST IAT_POSTQUITMESSAGE = 14

CONST IAT_ADDVECTOREDEXCEPTIONHANDLER = 15
CONST IAT_ADJUSTWINDOWRECTEX = 16
CONST IAT_ATAN = 17
CONST IAT_BEEP = 18
CONST IAT_BEGINPAINT = 19
CONST IAT_BITBLT = 20
CONST IAT_COS = 21
CONST IAT_CREATECOMPATIBLEBITMAP = 22
CONST IAT_CREATECOMPATIBLEDC = 23
CONST IAT_CREATEDIBSECTION = 24
CONST IAT_CREATEFONTA = 25
CONST IAT_CREATETHREAD = 26
CONST IAT_DELETEDC = 27
CONST IAT_DELETEOBJECT = 28
CONST IAT_DWMSETWINDOWATTRIBUTE = 29
CONST IAT_ENDPAINT = 30
CONST IAT_EXITTHREAD = 31
CONST IAT_GETASYNCKEYSTATE = 32
CONST IAT_GETPROCESSHEAP = 33
CONST IAT_GETSTOCKOBJECT = 34
CONST IAT_HEAPALLOC = 35
CONST IAT_HEAPFREE = 36
CONST IAT_INVALIDATERECT = 37
CONST IAT_LOADCURSORA = 38
CONST IAT_POW = 39
CONST IAT_SELECTOBJECT = 40
CONST IAT_SETBKCOLOR = 41
CONST IAT_SETCONSOLECURSORPOSITION = 42
CONST IAT_SETCONSOLETEXTATTRIBUTE = 43
CONST IAT_SETDIBCOLORTABLE = 44
CONST IAT_SETPIXEL = 45
CONST IAT_SETTEXTCOLOR = 46
CONST IAT_SIN = 47
CONST IAT_SLEEP = 48
CONST IAT_SPRINTF = 49
CONST IAT_STRETCHBLT = 50
CONST IAT_TEXTOUTA = 51
CONST IAT_UPDATEWINDOW = 52
CONST IAT_CREATEFILEA = 53
CONST IAT_CLOSEHANDLE = 54
CONST IAT_GETFILESIZE = 55
CONST IAT_DELETEFILEA = 56
CONST IAT_GETTICKCOUNT = 57
CONST IAT_GETSYSTEMMETRICS = 58
CONST IAT_SETWINDOWLONGA = 59
CONST IAT_SETWINDOWPOS = 60
CONST IAT_STRETCHDIBITS = 61
CONST IAT_GETKEYSTATE = 62
CONST IAT_KEYBD_EVENT = 63
CONST IAT_SRAND = 64
CONST IAT_GETCURSORPOS = 65
CONST IAT_SCREENTOCLIENT = 66


CONST PE_FILE_ALIGNMENT = &H200
CONST PE_FILE_HEADER_OFFSET = &H400
CONST PE_IDATA_RAW_SIZE = &H800
CONST PE_IMAGE_BASE = &H400000
CONST PE_MACHINE_AMD64 = &H8664
CONST PE_MAGIC_PE32PLUS = &H020B
CONST PE_NUM_SECTIONS = 2
CONST PE_OPT_HEADER_SIZE = &HF0
CONST PE_SECTION_ALIGNMENT = &H1000
CONST PE_TEXT_RVA = &H1000
CONST PE_TEXT_VA = PE_IMAGE_BASE + PE_TEXT_RVA

CONST TC_INVALID = 0 ' Tira Commands for tiraNew
CONST TC_ABI_EPILOGUE = 1
CONST TC_ABI_PROLOGUE = 2
CONST TC_ABI_READ_ARG = 3
CONST TC_ABI_WRITE_RET = 4
CONST TC_ADD = 5
CONST TC_ADDRESS_OF = 6
CONST TC_AND = 7
CONST TC_ASSIGN = 8
CONST TC_CALL = 9
CONST TC_CAST = 10
CONST TC_COMPARE = 11
CONST TC_CONCAT = 12
CONST TC_DIV = 13
CONST TC_ENTER_FRAME = 14
CONST TC_FREE_ARRAY = 15
CONST TC_GET_RET = 16
CONST TC_GET_RSP = 17
CONST TC_IDIV = 18
CONST TC_INTRINSIC = 19
CONST TC_JCC = 20
CONST TC_JMP = 21
CONST TC_JMP_COND = 22
CONST TC_JMP_USER = 23
CONST TC_LABEL = 24
CONST TC_LEAVE_FRAME = 25
CONST TC_MEMCPY = 26
CONST TC_MEMSET = 27
CONST TC_MOD = 28
CONST TC_MUL = 29
CONST TC_NEG = 30
CONST TC_NOT = 31
CONST TC_OR = 32
CONST TC_POW = 33
CONST TC_READ_MEM = 34
CONST TC_READ_MEM_OFFSET = 35
CONST TC_RESUME = 36
CONST TC_SHL = 37
CONST TC_SHR = 38
CONST TC_SUB = 39
CONST TC_SWAP_MEM = 40
CONST TC_TEST = 41
CONST TC_WRITE_MEM = 42
CONST TC_WRITE_MEM_OFFSET = 43
CONST TC_LEA_SIB = 44
CONST TC_SET_SUB_OFFSET = 45
CONST TC_MAIN_PROLOGUE = 46
CONST TC_BOUNDS_CHECK = 47
CONST TC_REDIM = 48
CONST TC_JMP_DYN = 49
CONST TC_XCHG = 50 ' Hardware atomic exchange instruction

CONST TC_OUTOFRANGE = 51


' Add new TC items here, and move TC_OUTOFRANGE to the end of them

CONST TEMP_HEAP_SIZE = 2097152

CONST GFX_ENTRY_LEN_OFFSET = 8

CONST SYMBOL_HASH_MAX = 8192 ' Defines the total count of slots in the symhash table, make sure it is a power of 2
CONST SYMBOL_HASH_MASK = SYMBOL_HASH_MAX - 1 ' The number above subtract 1, all 1s to AND against

CONST GFX_BUFFER_ENTRIES = 4096

CONST FRAMEBUF_MAX_WIDTH = 1024
CONST FRAMEBUF_MAX_HEIGHT = 1080

CONST COMP_IDLE = 0
CONST COMP_REFINE = 1
CONST COMP_COMPILE = 2
CONST COMP_SAVE = 3

CONST RT_INVALID = 0
CONST RT_KEYDOWN = 1
CONST RT_LINE = 2
CONST RT_PLOT_PIXEL = 3
CONST RT_STR_ASSIGN = 4
CONST RT_VEH_HANDLER = 5
CONST RT_PRINT_INT = 6
CONST RT_PRINT_FLOAT = 7
CONST RT_PRINT_STR = 8
CONST RT_CRLF = 9
CONST RT_INPUT = 10
CONST RT_GFX_APPEND = 11
CONST RT_STR_CMP = 12
CONST RT_GET = 13
CONST RT_PUT = 14
CONST RT_SWAP_BUFFERS = 15
CONST RT_FULLSCREEN = 16
CONST RT_AUTODISPLAY_CHECK = 17
CONST RT_CIRCLE = 18
CONST RT_READ = 19
CONST RT_MOUSEINPUT = 20


CONST CTRL_IF = 1
CONST CTRL_ELSE = 2
CONST CTRL_FOR = 3
CONST CTRL_DO = 4
CONST CTRL_SELECT = 5
CONST CTRL_WHILE = 6


CONST PATCH_VAR = 1
CONST PATCH_IAT = 2
CONST PATCH_GOTO = 4
CONST PATCH_RT = 5
CONST PATCH_CALL = 6

CONST TYPE_UNDEFINED = 0
CONST TYPE_LONG = 1
CONST TYPE_STRING = 2
CONST TYPE_BYTE = 3
CONST TYPE_ULONG = 4
CONST TYPE_UBYTE = 5
CONST TYPE_INTEGER64 = 6
CONST TYPE_UINT64 = 7
CONST TYPE_LABEL = 8
CONST TYPE_SINGLE = 9
CONST TYPE_DOUBLE = 10
CONST TYPE_UDT = 11 ' User defined type
CONST TYPE_INTEGER = 12
CONST TYPE_UINTEGER = 13
CONST TYPE_ANY = 99

CONST REG_NONE = 255

CONST OP_TYPE_REG = 5
CONST OP_TYPE_IMM = 6
CONST OP_TYPE_MEM_RIP = 7
CONST OP_TYPE_MEM_RSP = 8
CONST OP_TYPE_MEM_REG = 9
CONST OP_TYPE_MEM_REG_DISP8 = 10
CONST OP_TYPE_ACC = 11
CONST OP_TYPE_REG_ALT = 12
CONST OP_TYPE_MEM_RBP = 13
CONST OP_TYPE_MEM_REG_DISP32 = 14
CONST OP_TYPE_MEM_GS_ABS32 = 15
CONST OP_TYPE_MEM_GS_REG_DISP32 = 16

CONST MODE_IMM64 = 100 ' These are for opMov
CONST MODE_RIP = 101
CONST MODE_IMM8 = 102
CONST MODE_MOVZX32_8 = 103 ' movzx r32, r/m8
CONST MODE_MOVZX32_16 = 104 ' movzx r32, r/m16
CONST MODE_MOVZX64_8 = 105 ' movzx r64, r/m8
CONST MODE_MOVZX64_16 = 106 ' movzx r64, r/m16
CONST MODE_MOVSX32_8 = 107
CONST MODE_MOVSX32_16 = 108
CONST MODE_MOVSX64_8 = 109
CONST MODE_MOVSX64_16 = 110
CONST MODE_MOVSXD = 111

CONST ALU_ADD = 0
CONST ALU_OR = 1
CONST ALU_ADC = 2
CONST ALU_SBB = 3
CONST ALU_AND = 4
CONST ALU_SUB = 5
CONST ALU_XOR = 6
CONST ALU_CMP = 7

CONST JCC_JO = 0
CONST JCC_JNO = 1
CONST JCC_JB = 2
CONST JCC_JAE = 3
CONST JCC_JE = 4
CONST JCC_JNE = 5
CONST JCC_JBE = 6
CONST JCC_JA = 7
CONST JCC_JS = 8 ' Lacking infrastructure
CONST JCC_JNS = 9 ' Lacking infrastructure
CONST JCC_JP = 10 ' Lacking infrastructure
CONST JCC_JNP = 11 ' Lacking infrastructure
CONST JCC_JL = 12
CONST JCC_JGE = 13
CONST JCC_JLE = 14
CONST JCC_JG = 15
CONST JCC_JMP = 16

CONST JCC_MODE_FORWARD = 0
CONST JCC_MODE_BACKWARD = 1

CONST JCC_TYPE_SHORT = 0
CONST JCC_TYPE_NEAR = 1

CONST SHIFT_ROL = 0
CONST SHIFT_ROR = 1
CONST SHIFT_SHL = 4
CONST SHIFT_SHR = 5
CONST SHIFT_SAR = 7

CONST STR_MOVS = 0
CONST STR_CMPS = 1
CONST STR_STOS = 2
CONST STR_LODS = 3
CONST STR_SCAS = 4

CONST REP_NONE = 0 ' "Repeat" x86 commands
CONST REP_REP = 1
CONST REP_REPNE = 2

CONST UNARY_INC = 0
CONST UNARY_DEC = 1
CONST UNARY_NOT = 2
CONST UNARY_NEG = 3
CONST UNARY_MUL = 4
CONST UNARY_IMUL = 5
CONST UNARY_DIV = 6
CONST UNARY_IDIV = 7

CONST SSE_ADD = 0
CONST SSE_SUB = 1
CONST SSE_MUL = 2
CONST SSE_DIV = 3
CONST SSE_MOV = 4
CONST SSE_CVTSI2SD = 5
CONST SSE_CVTTSD2SI = 6 ' Convert with Truncation Scalar Double-precision floating-point value to a Signed Integer
CONST SSE_CVTSS2SD = 7
CONST SSE_MOVQ_XMM_REG = 8
CONST SSE_MOVQ_REG_XMM = 9
CONST SSE_UCOMI = 10
CONST SSE_XOR = 11
CONST SSE_CVTSD2SS = 12
CONST SSE_CVTSD2SI = 13 ' Convert Scalar Double-precision floating-point value to a Signed Integer - round to nearest even - notice only one T

CONST MODE_SSE_SINGLE = 1
CONST MODE_SSE_DOUBLE = 2

CONST MODE_IMUL32_REG = 200
CONST MODE_IMUL64_REG = 201
CONST MODE_IMUL32_IMM = 202
CONST MODE_IMUL64_IMM = 203
CONST MODE_IMUL32_IMM32 = 204
CONST MODE_IMUL64_IMM32 = 205

CONST CALLMODE_IAT = 300
CONST CALLMODE_REL32 = 301 ' Internal targets like user subroutines or runtime helpers use this

CONST FLAG_CLD = 0
CONST FLAG_STD = 1
CONST FLAG_CLI = 2
CONST FLAG_STI = 3
CONST FLAG_CLC = 4
CONST FLAG_STC = 5
CONST FLAG_CMC = 6

CONST EXTEND_CWD = 0
CONST EXTEND_CDQ = 1
CONST EXTEND_CQO = 2

'''' Data types

TYPE dataTypeCallPatchRecord
  Offset AS LONG
  SubIndex AS LONG
END TYPE: DIM SHARED callPatches(MAX_CALL_PATCHES) AS dataTypeCallPatchRecord

TYPE dataTypeColor
  flashTextClr AS LONG
  gray AS LONG
  focusBorder AS LONG
END TYPE: COMMON SHARED sysColor AS dataTypeColor

TYPE dataTypeCompileMetrics
  PrologueSize AS LONG
  EpilogueSize AS LONG
END TYPE: COMMON SHARED metrics AS dataTypeCompileMetrics

TYPE dataTypeCompilePass5
  SubState AS LONG
  Line AS LONG
  Success AS LONG
END TYPE: COMMON SHARED pass5 AS dataTypeCompilePass5

TYPE dataTypeCtrlRecord
  Type AS LONG
  Patch1 AS LONG
  Patch2 AS LONG
  ForVarIdx AS LONG
  SelectVarIdx AS LONG
  SelectDataType AS LONG
  SelectCaseSeen AS LONG
END TYPE: DIM SHARED ctrls(MAX_CTRLS) AS dataTypeCtrlRecord

TYPE dataTypeDeclare
  RecordName AS STRING * 64
  ArgCount AS LONG
  RetType AS LONG
  LineNumber AS LONG
  IsFunction AS LONG
END TYPE: DIM SHARED declares(MAX_SUBS) AS dataTypeDeclare

TYPE dataTypeEditor
  StartY AS LONG
  CursorX AS LONG
  CursorY AS LONG
  Focus AS LONG
  ScrollY AS LONG
  ScrollX AS LONG
  SelectStartX AS LONG
  SelectStartY AS LONG
  IsSelecting AS LONG
  LastLine AS LONG
  windowBarClr AS LONG
  windowBgClr AS LONG
  CloseClr AS LONG
  MenuMode AS LONG
  TopMenuFocus AS LONG
  MenuClicked AS LONG
  StatusScrollY AS LONG
  StatusSelectedIndex AS LONG
  ScrollDragActiveX AS LONG
  ScrollDragOffsetX AS LONG
  StatusScrollDragActive AS LONG
  StatusScrollDragOffsetY AS LONG
  HasCustomPalette AS LONG
  DragActive AS LONG
  ScrollDragActive AS LONG
  ScrollDragOffsetY AS LONG
  FuncScrollDragActive AS LONG
  FuncScrollDragOffsetY AS LONG
  TextLastClickTime AS DOUBLE
  TextClickActive AS LONG
  CornerLastClickTime AS DOUBLE
  CornerClickActive AS LONG
END TYPE: COMMON SHARED editor AS dataTypeEditor

TYPE dataTypeExpressionState
  DataType AS LONG
  IsTemp AS LONG
END TYPE: COMMON SHARED exprIs AS dataTypeExpressionState

TYPE dataTypeGotoPatchRecord
  Offset AS LONG
  VarIdx AS LONG
END TYPE: DIM SHARED gotoPatches(MAX_GOTO_PATCHES) AS dataTypeGotoPatchRecord

' Data type for our 8-bit color graphics setup, this stores the window size
TYPE dataTypeGraphicsConfig
  SizeX AS LONG
  SizeY AS LONG
END TYPE: COMMON SHARED gfxConfig AS dataTypeGraphicsConfig

TYPE dataTypeIatPatchRecord
  Offset AS LONG
  IATIdx AS LONG
END TYPE: DIM SHARED iatPatches(MAX_IAT_PATCHES) AS dataTypeIatPatchRecord

TYPE dataTypeImportDll
  DllName AS STRING * 32
  FuncCount AS LONG
  IltRVA AS LONG
  IatRVA AS LONG
  NameRVA AS LONG
END TYPE: DIM SHARED impDlls(10) AS dataTypeImportDll

TYPE dataTypeImportFunc
  FuncName AS STRING * 64
  FuncRVA AS LONG
END TYPE: DIM SHARED impFuncs(10, 32) AS dataTypeImportFunc

TYPE dataTypeImportTable
  numDlls AS LONG
  baseRVA AS LONG
  idtSize AS LONG
  totalIatSize AS LONG
  idataRawSize AS LONG
END TYPE: COMMON SHARED impTbl AS dataTypeImportTable

TYPE dataTypeIntrinsicDef
  TokenVal AS LONG
  ReturnType AS LONG
END TYPE: DIM SHARED intrinsicDefs(64) AS dataTypeIntrinsicDef

TYPE dataTypeKeyMap
  qbCode AS LONG
  vkCode AS LONG
END TYPE: DIM SHARED keyMapping(1024) AS dataTypeKeyMap

TYPE DataTypeLayout
  FramebufSize AS LONG
  GfxBufEntrySize AS LONG
  GfxBufEntryShift AS LONG
END TYPE: COMMON SHARED layout AS DataTypeLayout

TYPE dataTypeMouse
  Clicked1 AS LONG
  Clicked2 AS LONG
  Released1 AS LONG
  Released2 AS LONG
  PosX AS LONG
  PosY AS LONG
  Wheel AS LONG
  Button1Down AS LONG
  Button2Down AS LONG
  DownPosX AS LONG
  DownPosY AS LONG
  DownPosX2 AS LONG
  DownPosY2 AS LONG
END TYPE: COMMON SHARED mouse AS dataTypeMouse

TYPE dataTypePatchRecord
  Offset AS LONG
  VarIdx AS LONG
END TYPE: DIM SHARED patches(MAX_PATCHES) AS dataTypePatchRecord

TYPE dataTypeRuntime
  PatchCount AS LONG
END TYPE: COMMON SHARED rt AS dataTypeRuntime

DIM SHARED rtOffset(MAX_RT_ROUTINES) AS LONG

TYPE dataTypeRuntimePatchRecord
  Offset AS LONG
  Routine AS LONG
END TYPE: DIM SHARED rtPatches(MAX_RT_PATCHES) AS dataTypeRuntimePatchRecord

TYPE dataTypeStackLayout
  currentStackOffset AS LONG
  consoleFrameSize AS LONG

  GRAPHICS_MSG_SLOT AS LONG
  GFX_SETUP_FRAME AS LONG
  GFX_WNDPROC_FRAME AS LONG

  SETUP_SLOT_HINSTANCE AS LONG
  SETUP_SLOT_HWND AS LONG
  SETUP_SLOT_BITMAPINFO AS LONG

  WNDPROC_SLOT_HDC AS LONG
  WNDPROC_SLOT_COUNT AS LONG
  WNDPROC_SLOT_BASE AS LONG
  WNDPROC_SLOT_HWND AS LONG
  WNDPROC_SLOT_FB_X AS LONG
  WNDPROC_SLOT_FB_Y AS LONG
  WNDPROC_SLOT_FB_PTR AS LONG

  WNDPROC_SLOT_MEMDC AS LONG
  WNDPROC_SLOT_HBITMAP AS LONG
  WNDPROC_SLOT_OLD_HBITMAP AS LONG
  WNDPROC_SLOT_HFONT AS LONG
  WNDPROC_SLOT_OLD_HFONT AS LONG

  SETUP_SLOT_WNDCLASSEX AS LONG
  SETUP_SLOT_STYLE AS LONG
  SETUP_SLOT_LPFNWNDPROC AS LONG
  SETUP_SLOT_CBCLSEXTRA AS LONG
  SETUP_SLOT_CBWNDEXTRA AS LONG
  SETUP_SLOT_WNDCLASSEX_HINSTANCE AS LONG
  SETUP_SLOT_HICON AS LONG
  SETUP_SLOT_HCURSOR AS LONG
  SETUP_SLOT_HBRBACKGROUND AS LONG
  SETUP_SLOT_LPSZMENUNAME AS LONG
  SETUP_SLOT_LPSZCLASSNAME AS LONG
  SETUP_SLOT_HICONSM AS LONG

  SETUP_SLOT_X AS LONG
  SETUP_SLOT_Y AS LONG
  SETUP_SLOT_NWIDTH AS LONG
  SETUP_SLOT_NHEIGHT AS LONG
  SETUP_SLOT_RECT AS LONG
  SETUP_SLOT_HWNDPARENT AS LONG
  SETUP_SLOT_HMENU AS LONG
  SETUP_SLOT_CREATE_HINSTANCE AS LONG
  SETUP_SLOT_LPPARAM AS LONG

  WNDPROC_SLOT_PAINTSTRUCT AS LONG
  WNDPROC_SLOT_PAINTSTRUCT_PTR AS LONG
  WNDPROC_SLOT_MSG AS LONG
  WNDPROC_SLOT_WPARAM AS LONG
  WNDPROC_SLOT_LPARAM AS LONG
  WNDPROC_SLOT_RET AS LONG

  WNDPROC_SLOT_PIX_B AS LONG
  WNDPROC_SLOT_PIX_L AS LONG
  WNDPROC_SLOT_PAL_PTR AS LONG
  WNDPROC_SLOT_COLOR_ADDR AS LONG
  WNDPROC_SLOT_COLOR AS LONG
  WNDPROC_SLOT_BASE_ITR AS LONG
  WNDPROC_SLOT_CNT_ITR AS LONG
  WNDPROC_SLOT_X_VAL AS LONG
  WNDPROC_SLOT_Y_VAL AS LONG
  WNDPROC_SLOT_STR_PTR AS LONG
  WNDPROC_SLOT_LEN_VAL AS LONG
  WNDPROC_SLOT_MAPPED_KEY AS LONG
  WNDPROC_SLOT_KEY_STATE AS LONG
  WNDPROC_SLOT_FONT_PTR AS LONG
  WNDPROC_SLOT_BITMAPINFO AS LONG

  WNDPROC_SLOT_CHAR_HEAD_PTR AS LONG
  WNDPROC_SLOT_CHAR_HEAD_VAL AS LONG
  WNDPROC_SLOT_CHAR_NEXTHEAD AS LONG
  WNDPROC_SLOT_CHAR_TAIL_PTR AS LONG
  WNDPROC_SLOT_CHAR_TAIL_VAL AS LONG
  WNDPROC_SLOT_CHAR_BUF_PTR AS LONG
  WNDPROC_SLOT_CHAR_TARGET AS LONG

  stackIs16Aligned AS LONG ' 1 if properly aligned at a 16 byte boundary, prevents system call crashes

END TYPE: COMMON SHARED stack AS dataTypeStackLayout

TYPE dataTypeBinaryStream
  emitPos AS LONG
END TYPE: DIM SHARED stream AS dataTypeBinaryStream

TYPE dataTypeSubRecord
  RecordName AS STRING * 64
  Offset AS LONG
  JmpPatchPos AS LONG
  ArgCount AS LONG
  ScopeID AS LONG
  ReturnVarIdx AS LONG
  LocalFrameSize AS LONG
  ExitPatchList AS LONG ' Track EXIT SUB jumps
  IsFunction AS LONG
END TYPE: DIM SHARED subs(MAX_SUBS) AS dataTypeSubRecord

TYPE dataTypeSymbolRecord
  RecordName AS STRING * 64
  DataType AS LONG
  ScopeID AS LONG
  IsShared AS LONG
  IsArray AS LONG
  Offset AS LONG
  Size AS LONG
  Size2 AS LONG
  HashNext AS LONG
  SubIndex AS LONG
  UDTIndex AS LONG
  IsExplicit AS LONG
  IsLocal AS LONG
  LocalOffset AS LONG
  DescOffset AS LONG
  StrOffset AS LONG
  alreadyParsed AS LONG ' For use with labels
  FixedStrLen AS LONG
  DataIndex AS LONG
END TYPE: DIM SHARED symbols(MAX_SYMBOLS) AS dataTypeSymbolRecord ' Symbols are identifiers, variable names and constant names

TYPE dataTypeTextConst
  Name AS STRING
  Value AS STRING
END TYPE: DIM SHARED textConsts(MAX_TEXT_CONSTS) AS dataTypeTextConst

TYPE dataTypeTextLayout
  CodeOffset AS LONG
  CodeSize AS LONG
  StrBase AS LONG
  VarBase AS LONG
  DescBase AS LONG
  GfxBufFrontBase AS LONG
  GfxBufBackBase AS LONG
  HwndBase AS LONG
  MemDCBase AS LONG
  DIBPtrBase AS LONG
  HBitmapBase AS LONG
  FramebufFrontBase AS LONG
  FramebufBackBase AS LONG
  KbdBufBase AS LONG
  KbdHeadBase AS LONG
  KbdTailBase AS LONG
  FileHandlesBase AS LONG
  DataPtrArrBase AS LONG
  KbdStateBase AS LONG
  TotalSize AS LONG
  TotalStrSize AS LONG
  TotalVarSize AS LONG
  TotalDescSize AS LONG
  MouseBufBase AS LONG
  MouseHeadBase AS LONG
  MouseTailBase AS LONG
END TYPE: COMMON SHARED textLayout AS dataTypeTextLayout

TYPE dataTypeTira

  LineCount AS LONG
  IsActive AS LONG
  TempCounter AS LONG ' Suffix counter for intermediate variables like ~T_0; resets to 0 per statement
  TiraVarCounter AS LONG ' A deterministic counter reset at the start of compilation to assign unique IDs
  ' to shunting yard temporaries, literal constants, and control blocks. Prevents symbol table desyncs across multi-pass compilation
  ' Decouples temporary variables from volatile symbolCount to map cleanly across both passes

END TYPE: COMMON SHARED t AS dataTypeTira

TYPE dataTypeUDT
  RecordName AS STRING * 64
  FieldCount AS LONG
  TotalSize AS LONG
END TYPE: DIM SHARED udts(64) AS dataTypeUDT

TYPE dataTypeUDTField
  FieldName AS STRING * 64
  DataType AS LONG
  Offset AS LONG
  Size AS LONG
  UDTIndex AS LONG
  IsDynamicString AS LONG
END TYPE: DIM SHARED udtFields(64, 64) AS dataTypeUDTField

TYPE dataTypeUndo
  CursorX AS LONG
  CursorY AS LONG
  ScrollX AS LONG
  ScrollY AS LONG
  LastLine AS LONG
  Ready AS LONG
END TYPE: COMMON SHARED undoState AS dataTypeUndo

TYPE dataTypeVocabulary ' Store strings for keywords, and possibly for whether they are pre-processors
  text AS STRING
  IsPreprocessor AS LONG
END TYPE: DIM SHARED voc(1024) AS dataTypeVocabulary

COMMON SHARED returnF2data ' Send a second value back, set to what you want, retrieve by returnedData2 function
COMMON SHARED returnF3data ' Send a second value back, set to what you want, retrieve by return3 function

COMMON SHARED fileNameBMP$
COMMON SHARED fileNameCode$
COMMON SHARED fileNameOut$
COMMON SHARED fileNameErr$
COMMON SHARED lastKeyPress
COMMON SHARED flashText$, flashTextTimer
COMMON SHARED outputFileIdx AS LONG

COMMON SHARED compileStatusMsg$
COMMON SHARED compileState
COMMON SHARED compileLastLine AS LONG

DIM SHARED tiraCmd(MAX_TIRA_LINES) AS LONG

COMMON SHARED callPatchCount AS LONG
COMMON SHARED compileClassicMode AS LONG ' Refine process will allow for duck-typing of variables when set
COMMON SHARED compileStringStrict AS LONG ' Requires * length on STRING when active
COMMON SHARED compileGraphicsDouble
COMMON SHARED compileHasGraphics
COMMON SHARED compileWindowTitle$
COMMON SHARED ctrlCount AS LONG
COMMON SHARED currentLineNumber AS INTEGER
COMMON SHARED currentSubName$
COMMON SHARED defaultArrayDynamic AS LONG
COMMON SHARED editorSearchQuery$
COMMON SHARED expectedSymType AS LONG
COMMON SHARED funcScrollY AS LONG
COMMON SHARED gotoPatchCount AS LONG
COMMON SHARED iatPatchCount
COMMON SHARED insideSub AS LONG
COMMON SHARED intrinsicCount AS LONG
COMMON SHARED isDummyPass AS LONG
COMMON SHARED isFullscreen
COMMON SHARED keyMappingCount AS LONG
COMMON SHARED lastNumericLabel AS LONG
COMMON SHARED lineTokenCount ' Tracks the number of syntax elements currently stored in the lineTokens$ array for the active line
COMMON SHARED patchCount
COMMON SHARED subCount AS LONG
COMMON SHARED symbolCount AS LONG
COMMON SHARED textConstCount AS LONG
COMMON SHARED udtCount AS LONG
COMMON SHARED uiSubCount

COMMON SHARED scopeCounter AS LONG ' Could these be in a data type?
COMMON SHARED currentScopeID AS LONG

COMMON SHARED statusMsgCount
COMMON SHARED currentFrameSize AS LONG

COMMON SHARED internalTempHeapSymbolIdx AS LONG ' Caches !TEMP_HEAP_PTR symbol index for x64 string concatenation inside tasm_DoMath

COMMON SHARED lastActionWasTyping AS LONG
COMMON SHARED declareCount AS LONG
COMMON SHARED dataItemCount AS LONG

DIM SHARED intermediateCode(1048576) AS _UNSIGNED _BYTE
DIM SHARED symHash(SYMBOL_HASH_MASK) AS LONG
DIM SHARED dataItemDescIdx(10000) AS LONG

DIM SHARED defIntMap(25) AS LONG ' The 26 letters, C would be stored in the third slot

' The lineTokens$() array is completely overwritten every time the tokenizeLine subroutine processes a new line of code.
DIM SHARED lineTokens$(MAX_TOKENS) ' Temporarily stores the current line's syntax elements and is completely overwritten every time a new line is tokenized
DIM SHARED lineTokenVals(MAX_TOKENS) AS LONG ' Stores the pre-calculated retTokenVal of the parallel string array to bypass repeated parsing loops

DIM SHARED rtIsUsed(MAX_RT_ROUTINES) AS LONG

DIM SHARED compileText$(COMPILE_LINE_MAX)
DIM SHARED bmpPal256(256, 4) AS _UNSIGNED _BYTE
DIM SHARED outputPal(256, 4) AS _UNSIGNED _BYTE
DIM SHARED fontData(256, 256) AS _UNSIGNED _BYTE
DIM SHARED outputFile(16777216) AS _UNSIGNED _BYTE
DIM SHARED editorText$(EDITOR_LINE_MAX)
DIM SHARED editorLineLinkMap(COMPILE_LINE_MAX) AS LONG ' Links the flattened code to the original string array

DIM SHARED declareArgType(MAX_SUBS, 16) AS LONG
DIM SHARED declareArgArray(MAX_SUBS, 16) AS LONG

DIM SHARED floatVarData(MAX_SYMBOLS) AS DOUBLE

DIM SHARED impFlatIatRVA(256) AS LONG
DIM SHARED impIatFlatIdx(256) AS LONG

DIM SHARED uiSubName$(MAX_UI_SUBS)
DIM SHARED uiSubLine(MAX_UI_SUBS) AS LONG

' Literal Pool: strVarData$() stores static literal string constants and initial
' spaces for fixed-length string variables. Runtime temporary allocations and
' dynamic string evaluations are managed on the thread-local temporary heap.

DIM SHARED strVarData$(MAX_SYMBOLS)

DIM SHARED statusMsg$(1000)
DIM SHARED subArgVarIdx(MAX_SUBS, 16) AS LONG

DIM SHARED undoText$(EDITOR_LINE_MAX)

DIM SHARED tiraCode$(MAX_TIRA_LINES)

COMMON SHARED isCompilingRT AS LONG
COMMON SHARED rtWrapperActive AS LONG
COMMON SHARED rtFrameSize AS LONG

COMMON SHARED compileEmeraldMode AS LONG

RANDOMIZE TIMER

initFileNames
initPalettesBmp
initPalettesOutput
initColors
initKeywords
initIntrinsics
initKeyMapping ' For command _KEYDOWN
createFont
initLayout

' Set default colors before attempting to load bitmap which might override them
editor.windowBarClr = 208
editor.windowBgClr = 0

editor.CloseClr = 4

fileBitmapLoad
setPalettes256 ' Send the stored colors to the hardware

' EpilogueSize is measured dynamically in prepareBinary and stored here for reference
metrics.EpilogueSize = 0

editor.Focus = 1

a_Main

END

''''''''''''''''''''''''
SUB a_Main

  editor.DragActive = 0
  isFullscreen = 1

  DO ' Start of main loop

    mouseReadInput
    limitSpeed

    processInput
    processCompileState

    redrawAll
    _DISPLAY

  LOOP ' End of main loop

END SUB ' a_Main

''''''''''''''''''''''''
SUB addIntrinsic (passKw$, passReturnType)

  tokVal = 0

  FOR ii = 512 TO 1023
    IF voc(ii).text = passKw$ THEN
      tokVal = ii
      EXIT FOR
    END IF
  NEXT

  IF tokVal = 0 THEN
    ESCAPETEXT "ERROR: Intrinsic keyword not found: " + passKw$
  END IF

  intrinsicDefs(intrinsicCount).TokenVal = tokVal
  intrinsicDefs(intrinsicCount).ReturnType = passReturnType
  intrinsicCount = intrinsicCount + 1

END SUB ' addIntrinsic

''''''''''''''''''''''''
SUB addKeyword (passKw$, passTokVal, passIsPre)

  voc(passTokVal).text = passKw$
  voc(passTokVal).IsPreprocessor = passIsPre

END SUB ' addKeyword

''''''''''''''''''''''''
SUB addPatch (passType, passOffset, passTargetInt)

  IF isDummyPass = 1 THEN EXIT SUB

  SELECT CASE passType

    CASE PATCH_VAR
      IF patchCount >= MAX_PATCHES THEN
        throwCompilerError "PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      patches(patchCount).Offset = passOffset
      patches(patchCount).VarIdx = passTargetInt
      patchCount = patchCount + 1

    CASE PATCH_IAT
      IF iatPatchCount >= MAX_IAT_PATCHES THEN
        throwCompilerError "IAT PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      iatPatches(iatPatchCount).Offset = passOffset
      iatPatches(iatPatchCount).IATIdx = passTargetInt
      iatPatchCount = iatPatchCount + 1

    CASE PATCH_GOTO
      IF gotoPatchCount >= MAX_GOTO_PATCHES THEN
        throwCompilerError "GOTO PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      gotoPatches(gotoPatchCount).Offset = passOffset
      gotoPatches(gotoPatchCount).VarIdx = passTargetInt
      gotoPatchCount = gotoPatchCount + 1

    CASE PATCH_RT
      IF rt.PatchCount >= MAX_RT_PATCHES THEN
        throwCompilerError "RT PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      rtPatches(rt.PatchCount).Offset = passOffset
      rtPatches(rt.PatchCount).Routine = passTargetInt
      rt.PatchCount = rt.PatchCount + 1

    CASE PATCH_CALL
      IF callPatchCount >= MAX_CALL_PATCHES THEN
        throwCompilerError "CALL PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      callPatches(callPatchCount).Offset = passOffset
      callPatches(callPatchCount).SubIndex = passTargetInt
      callPatchCount = callPatchCount + 1

  END SELECT ' passType

END SUB ' addPatch

''''''''''''''''''''''''
SUB addStatusMsg (wMsg$)

  compileStatusMsg$ = wMsg$

  editorTextX = EDITOR_BOX_X + LEFT_SPACING
  editorTextW = 56 * 8
  statusBoxW = editorTextX + editorTextW + 3

  maxLen = (statusBoxW - 16) \ 8

  tempMsg$ = wMsg$
  DO WHILE LEN(tempMsg$) > 0
    IF LEN(tempMsg$) <= maxLen THEN
      pushStatusMsg tempMsg$
      tempMsg$ = ""
    ELSE
      splitPos = maxLen
      FOR ii = maxLen TO 1 STEP -1
        IF MID$(tempMsg$, ii, 1) = " " THEN
          splitPos = ii
          EXIT FOR
        END IF
      NEXT
      IF splitPos = maxLen THEN
        pushStatusMsg LEFT$(tempMsg$, maxLen)
        tempMsg$ = MID$(tempMsg$, maxLen + 1)
      ELSE
        pushStatusMsg LEFT$(tempMsg$, splitPos - 1)
        tempMsg$ = MID$(tempMsg$, splitPos + 1)
      END IF
    END IF
  LOOP

END SUB ' addStatusMsg

''''''''''''''''''''''''
FUNCTION addStackSpace (wSize)

  tempOffset = currentFrameSize
  currentFrameSize = currentFrameSize + wSize
  addStackSpace = tempOffset

END FUNCTION ' addStackSpace

''''''''''''''''''''''''
SUB adjustAllPatchOffsets (offsetDiff, userPatchCnt, userIatPatchCnt, userGotoPatchCnt, userCallPatchCnt, userRtPatchCnt, userSubCnt, userSymbolCnt)

  FOR ii = 0 TO userPatchCnt - 1
    patches(ii).Offset = patches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userIatPatchCnt - 1
    iatPatches(ii).Offset = iatPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userGotoPatchCnt - 1
    gotoPatches(ii).Offset = gotoPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userSymbolCnt - 1
    IF symbols(ii).DataType = TYPE_LABEL THEN
      symbols(ii).Offset = symbols(ii).Offset + offsetDiff
    END IF
  NEXT
  FOR ii = 0 TO userCallPatchCnt - 1
    callPatches(ii).Offset = callPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userRtPatchCnt - 1
    rtPatches(ii).Offset = rtPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userSubCnt - 1
    subs(ii).Offset = subs(ii).Offset + offsetDiff
  NEXT

  ' Shift the absolute runtime entry point offsets
  FOR ii = 0 TO MAX_RT_ROUTINES
    rtOffset(ii) = rtOffset(ii) + offsetDiff
  NEXT

END SUB ' adjustAllPatchOffsets

''''''''''''''''''''''''
FUNCTION alignStackFrame

  remainder = currentFrameSize MOD 16

  SELECT CASE remainder

    CASE 0
      currentFrameSize = currentFrameSize + 8
    CASE 1 TO 7
      currentFrameSize = currentFrameSize + (8 - remainder)
    CASE 8
      ' The frame is already perfectly aligned for Windows x64 API calls (16-byte aligned minus 8)
    CASE IS > 8
      currentFrameSize = currentFrameSize + (24 - remainder)

  END SELECT ' remainder

  alignStackFrame = currentFrameSize

END FUNCTION ' alignStackFrame

''''''''''''''''''''''''
SUB arrayPadNumBytes (wCount, wValue)

  FOR ii = 1 TO wCount
    outputFile(outputFileIdx) = wValue
    outputFileIdx = outputFileIdx + 1
  NEXT

END SUB ' arrayPadNumBytes

''''''''''''''''''''''''
SUB arrayPadUpTo (wAddress, wValue)

  IF outputFileIdx < wAddress THEN
    padCount = wAddress - outputFileIdx
    arrayPadNumBytes padCount, wValue
  END IF

END SUB ' arraypadUpTo

''''''''''''''''''''''''
SUB arrayWrite16LE (wVal)

  ' writes little endian

  DIM uVal AS _UNSIGNED LONG
  DIM byte0 AS _UNSIGNED _BYTE
  DIM byte1 AS _UNSIGNED _BYTE

  uVal = wVal AND 65535

  byte0 = uVal AND 255
  byte1 = (uVal \ 256) AND 255

  outputFile(outputFileIdx) = byte0
  outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = byte1
  outputFileIdx = outputFileIdx + 1

END SUB ' arrayWrite16LE

''''''''''''''''''''''''
SUB arrayWrite32F (wVal AS SINGLE)

  ' Float version, little endian

  DIM vStr AS STRING * 4

  vStr = MKS$(wVal)
  FOR ii = 1 TO 4
    outputFile(outputFileIdx) = ASC(MID$(vStr, ii, 1))
    outputFileIdx = outputFileIdx + 1
  NEXT

END SUB ' arrayWrite32F

''''''''''''''''''''''''
SUB arrayWrite32LE (wVal AS _UNSIGNED LONG)

  ' writes little endian

  DIM uVal AS _UNSIGNED LONG
  DIM byte0 AS _UNSIGNED _BYTE
  DIM byte1 AS _UNSIGNED _BYTE
  DIM byte2 AS _UNSIGNED _BYTE
  DIM byte3 AS _UNSIGNED _BYTE

  uVal = wVal

  byte0 = uVal AND 255
  byte1 = (uVal \ 256) AND 255
  byte2 = (uVal \ 65536) AND 255
  byte3 = (uVal \ 16777216) AND 255

  outputFile(outputFileIdx) = byte0
  outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = byte1
  outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = byte2
  outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = byte3
  outputFileIdx = outputFileIdx + 1

END SUB ' arrayWrite32LE

''''''''''''''''''''''''
SUB arrayWrite64F (wVal AS DOUBLE)

  ' Float version, little endian

  DIM vStr AS STRING * 8

  vStr = MKD$(wVal)
  FOR ii = 1 TO 8
    outputFile(outputFileIdx) = ASC(MID$(vStr, ii, 1))
    outputFileIdx = outputFileIdx + 1
  NEXT

END SUB ' arrayWrite64F

''''''''''''''''''''''''
SUB arrayWriteCharString (wStr$)

  FOR ii = 1 TO LEN(wStr$)
    outputFile(outputFileIdx) = ASC(MID$(wStr$, ii, 1))
    outputFileIdx = outputFileIdx + 1
  NEXT

END SUB ' arrayWriteCharString

''''''''''''''''''''''''
SUB buildImportTable

  impTbl.numDlls = 5

  impDlls(0).DllName = "KERNEL32.dll"
  impDlls(0).FuncCount = 21
  impFuncs(0, 0).FuncName = "GetStdHandle"
  impFuncs(0, 1).FuncName = "WriteFile"
  impFuncs(0, 2).FuncName = "ReadFile"
  impFuncs(0, 3).FuncName = "ExitProcess"
  impFuncs(0, 4).FuncName = "GetModuleHandleA"
  impFuncs(0, 5).FuncName = "SetConsoleMode"
  impFuncs(0, 6).FuncName = "AddVectoredExceptionHandler"
  impFuncs(0, 7).FuncName = "Beep"
  impFuncs(0, 8).FuncName = "CreateThread"
  impFuncs(0, 9).FuncName = "ExitThread" ' Cleanly terminates the calling thread. The proper way to shut down an individual thread without terminating the parent process
  impFuncs(0, 10).FuncName = "GetProcessHeap"
  impFuncs(0, 11).FuncName = "HeapAlloc"
  impFuncs(0, 12).FuncName = "HeapFree"
  impFuncs(0, 13).FuncName = "SetConsoleCursorPosition"
  impFuncs(0, 14).FuncName = "SetConsoleTextAttribute"
  impFuncs(0, 15).FuncName = "Sleep"
  impFuncs(0, 16).FuncName = "CreateFileA"
  impFuncs(0, 17).FuncName = "CloseHandle"
  impFuncs(0, 18).FuncName = "GetFileSize"
  impFuncs(0, 19).FuncName = "DeleteFileA"
  impFuncs(0, 20).FuncName = "GetTickCount"

  impDlls(1).DllName = "USER32.dll"
  impDlls(1).FuncCount = 22
  impFuncs(1, 0).FuncName = "DefWindowProcA"
  impFuncs(1, 1).FuncName = "RegisterClassExA"
  impFuncs(1, 2).FuncName = "CreateWindowExA"
  impFuncs(1, 3).FuncName = "ShowWindow"
  impFuncs(1, 4).FuncName = "PeekMessageA"
  impFuncs(1, 5).FuncName = "TranslateMessage"
  impFuncs(1, 6).FuncName = "DispatchMessageA"
  impFuncs(1, 7).FuncName = "PostQuitMessage"
  impFuncs(1, 8).FuncName = "AdjustWindowRectEx"
  impFuncs(1, 9).FuncName = "BeginPaint"
  impFuncs(1, 10).FuncName = "EndPaint"
  impFuncs(1, 11).FuncName = "GetAsyncKeyState"
  impFuncs(1, 12).FuncName = "InvalidateRect"
  impFuncs(1, 13).FuncName = "LoadCursorA"
  impFuncs(1, 14).FuncName = "UpdateWindow"
  impFuncs(1, 15).FuncName = "GetSystemMetrics"
  impFuncs(1, 16).FuncName = "SetWindowLongA"
  impFuncs(1, 17).FuncName = "SetWindowPos"
  impFuncs(1, 18).FuncName = "GetKeyState"
  impFuncs(1, 19).FuncName = "keybd_event"
  impFuncs(1, 20).FuncName = "GetCursorPos"
  impFuncs(1, 21).FuncName = "ScreenToClient"

  impDlls(2).DllName = "GDI32.dll"
  impDlls(2).FuncCount = 16
  impFuncs(2, 0).FuncName = "BitBlt"
  impFuncs(2, 1).FuncName = "CreateCompatibleBitmap"
  impFuncs(2, 2).FuncName = "CreateCompatibleDC"
  impFuncs(2, 3).FuncName = "CreateDIBSection" ' Creates a Device-Independent Bitmap (DIB) that the program can write to directly. Allocates memory for the bitmap's pixels and hands off a direct memory pointer to those pixels
  impFuncs(2, 4).FuncName = "CreateFontA"
  impFuncs(2, 5).FuncName = "DeleteDC"
  impFuncs(2, 6).FuncName = "DeleteObject"
  impFuncs(2, 7).FuncName = "GetStockObject"
  impFuncs(2, 8).FuncName = "SelectObject"
  impFuncs(2, 9).FuncName = "SetBkColor"
  impFuncs(2, 10).FuncName = "SetDIBColorTable"
  impFuncs(2, 11).FuncName = "SetPixel"
  impFuncs(2, 12).FuncName = "SetTextColor"
  impFuncs(2, 13).FuncName = "StretchBlt"
  impFuncs(2, 14).FuncName = "TextOutA"
  impFuncs(2, 15).FuncName = "StretchDIBits"

  impDlls(3).DllName = "DWMAPI.dll"
  impDlls(3).FuncCount = 1
  impFuncs(3, 0).FuncName = "DwmSetWindowAttribute"

  impDlls(4).DllName = "msvcrt.dll"
  impDlls(4).FuncCount = 6
  impFuncs(4, 0).FuncName = "atan"
  impFuncs(4, 1).FuncName = "cos"
  impFuncs(4, 2).FuncName = "pow"
  impFuncs(4, 3).FuncName = "sin"
  impFuncs(4, 4).FuncName = "sprintf"
  impFuncs(4, 5).FuncName = "srand"

  currentRVA = impTbl.baseRVA

  impTbl.idtSize = (impTbl.numDlls + 1) * 20
  currentRVA = currentRVA + impTbl.idtSize

  FOR iDll = 0 TO impTbl.numDlls - 1
    impDlls(iDll).IltRVA = currentRVA
    iltSize = (impDlls(iDll).FuncCount + 1) * 8
    currentRVA = currentRVA + iltSize
  NEXT

  impTbl.totalIatSize = 0
  FOR iDll = 0 TO impTbl.numDlls - 1
    impDlls(iDll).IatRVA = currentRVA
    iatSize = (impDlls(iDll).FuncCount + 1) * 8
    impTbl.totalIatSize = impTbl.totalIatSize + iatSize
    currentRVA = currentRVA + iatSize
  NEXT

  flatIdx = 0
  FOR iDll = 0 TO impTbl.numDlls - 1
    FOR iFunc = 0 TO impDlls(iDll).FuncCount - 1
      impFuncs(iDll, iFunc).FuncRVA = currentRVA
      impFlatIatRVA(flatIdx) = impDlls(iDll).IatRVA + (iFunc * 8)
      flatIdx = flatIdx + 1

      fName$ = RTRIM$(impFuncs(iDll, iFunc).FuncName)
      nameLen = LEN(fName$) + 1
      entrySize = 2 + nameLen
      IF (entrySize AND 1) <> 0 THEN entrySize = entrySize + 1
      currentRVA = currentRVA + entrySize
    NEXT
  NEXT

  flatIdx = 0
  FOR iDll = 0 TO impTbl.numDlls - 1
    FOR iFunc = 0 TO impDlls(iDll).FuncCount - 1
      fName$ = RTRIM$(impFuncs(iDll, iFunc).FuncName)
      iatConst = retIatConstByName(fName$, 0)
      IF iatConst <> IAT_INVALID THEN
        impIatFlatIdx(iatConst) = flatIdx
      END IF
      flatIdx = flatIdx + 1
    NEXT
  NEXT

  FOR iDll = 0 TO impTbl.numDlls - 1
    impDlls(iDll).NameRVA = currentRVA
    dName$ = RTRIM$(impDlls(iDll).DllName)
    nameLen = LEN(dName$) + 1
    IF (nameLen AND 1) <> 0 THEN nameLen = nameLen + 1
    currentRVA = currentRVA + nameLen
  NEXT

  exactIdataSize = currentRVA - impTbl.baseRVA
  impTbl.idataRawSize = ((exactIdataSize + PE_FILE_ALIGNMENT - 1) \ PE_FILE_ALIGNMENT) * PE_FILE_ALIGNMENT

END SUB ' buildImportTable

''''''''''''''''''''''''
FUNCTION calcRex (opSize AS LONG, regR AS LONG, regB AS LONG, regX AS LONG)

  DIM rexByte AS LONG
  rexByte = 0

  IF opSize = 64 THEN rexByte = rexByte OR &H08
  IF regR >= 8 THEN
    IF regR <> REG_NONE THEN rexByte = rexByte OR &H04
  END IF
  IF regX >= 8 THEN
    IF regX <> REG_NONE THEN rexByte = rexByte OR &H02
  END IF
  IF regB >= 8 THEN
    IF regB <> REG_NONE THEN rexByte = rexByte OR &H01
  END IF

  IF opSize = 8 THEN
    IF regR >= 4 AND regR <= 7 THEN
      rexByte = rexByte OR &H40
    ELSE
      IF regB >= 4 AND regB <= 7 THEN
        rexByte = rexByte OR &H40
      END IF
    END IF
  END IF

  IF rexByte > 0 THEN rexByte = rexByte OR &H40

  calcRex = rexByte

END FUNCTION ' calcRex

''''''''''''''''''''''''
SUB checkEmergencyClose

  closeBtnW = 15
  closeBtnX = SCREENSIZEX - closeBtnW
  closeBtnY = 0
  closeBtnH = 13

  mouseReadInput
  IF mouseClickedInBox(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
    compileStatusMsg$ = "ERROR: ABORTED BY USER"
    editor.TopMenuFocus = 4
    editor.Focus = 0
    editor.MenuClicked = 1
  END IF

END SUB ' checkEmergencyClose

''''''''''''''''''''''''
FUNCTION checkExpressionForString (startIdx, endIdx)

  DIM isStringExpr AS LONG
  DIM iLook AS LONG
  DIM tValL AS LONG
  DIM lookIdx AS LONG
  DIM lookTok$

  isStringExpr = 0
  FOR iLook = startIdx TO endIdx
    tValL = lineTokenVals(iLook)
    IF tValL = 256 + ASC("(") THEN
      ' Ignore opening parenthesis and keep looking for the first operand
    ELSE
      IF tValL = 0 THEN
        lookTok$ = lineTokens$(iLook)
        IF LEFT$(lookTok$, 1) = CHR$(34) THEN
          isStringExpr = 1
          EXIT FOR
        END IF
        IF RIGHT$(lookTok$, 1) = "$" THEN
          isStringExpr = 1
          EXIT FOR
        END IF
        ff = findSymbol(UCASE$(lookTok$))
        IF ff = 1 THEN
          lookIdx = returnedData2
          IF symbols(lookIdx).DataType = TYPE_STRING THEN
            isStringExpr = 1
            EXIT FOR
          END IF
        END IF
        EXIT FOR ' If it's a numeric variable/function or literal, it's numeric
      ELSE
        ' Intrinsic or operator
        IF tValL = TOK_CHR OR tValL = TOK_STR OR tValL = TOK_LTRIM OR tValL = TOK_RTRIM OR tValL = TOK_UCASE OR tValL = TOK_INKEY OR tValL = TOK_INKEYF OR tValL = TOK_LEFT OR tValL = TOK_RIGHT OR tValL = TOK_MID THEN
          isStringExpr = 1
        END IF
        EXIT FOR ' Stop at the first operative keyword
      END IF
    END IF
  NEXT

  checkExpressionForString = isStringExpr

END FUNCTION ' checkExpressionForString

''''''''''''''''''''''''
SUB checkRegisterBounds (wReg, wName$)

  IF wReg < 0 OR wReg > 15 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: Register out of bounds (" + LTRIM$(STR$(wReg)) + ") in " + wName$
  END IF

END SUB ' checkRegisterBounds

''''''''''''''''''''''''
SUB collapseTokens (startIdx, endIdx, repVar$)

  DIM shiftDist AS LONG

  shiftDist = endIdx - startIdx

  ' Overwrite the intrinsic call with the calculated !HOIST variable
  lineTokens$(startIdx) = repVar$
  lineTokenVals(startIdx) = 0 ' Null the value so the system treats it as an identifier

  ' Shift the remaining line elements leftwards to fill the gap
  FOR ii = endIdx + 1 TO lineTokenCount - 1
    lineTokens$(ii - shiftDist) = lineTokens$(ii)
    lineTokenVals(ii - shiftDist) = lineTokenVals(ii)
  NEXT

  lineTokenCount = lineTokenCount - shiftDist

END SUB ' collapseTokens

''''''''''''''''''''''''
FUNCTION compile

  currentLineNumber = 1
  compileStatusMsg$ = ""
  stream.emitPos = 0

  FOR ii = 0 TO MAX_SYMBOLS
    strVarData$(ii) = ""
    floatVarData(ii) = 0
  NEXT

  symbolCount = 0
  scopeCounter = 0
  currentScopeID = 0 ' Start in the global scope
  lineTokenCount = 0
  patchCount = 0
  iatPatchCount = 0
  compileHasGraphics = 0
  compileGraphicsDouble = 0
  compileClassicMode = 0
  compileStringStrict = 0
  compileEmeraldMode = 0
  compileHasGlobalDefInt = 0
  expectedSymType = TYPE_ANY
  compileWindowTitle$ = "Default"

  FOR iy = 1 TO editor.LastLine
    tempScan$ = UCASE$(LTRIM$(RTRIM$(editorText$(iy))))
    IF LEFT$(tempScan$, 1) = "'" THEN tempScan$ = LTRIM$(MID$(tempScan$, 2))
    IF LEFT$(tempScan$, 8) = "#EMERALD" THEN
      compileEmeraldMode = 1
      compileStringStrict = 1
    END IF
  NEXT

  ctrlCount = 0
  gotoPatchCount = 0
  lastNumericLabel = 0 ' 0 is not a valid label, so signals invalid
  t.TiraVarCounter = 0

  t.LineCount = 0
  t.TempCounter = 0
  t.IsActive = 3

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 0

  rt.PatchCount = 0

  FOR ii = 0 TO MAX_RT_ROUTINES
    rtIsUsed(ii) = 0
    rtOffset(ii) = 0
  NEXT

  FOR ii = 0 TO 25
    defIntMap(ii) = 0
  NEXT

  subCount = 1 ' Starts at 1 to reserve 0 for the main program
  subs(0).RecordName = "MAIN"
  subs(0).ScopeID = 0
  subs(0).IsFunction = 0
  subs(0).ArgCount = 0
  subs(0).LocalFrameSize = 0

  callPatchCount = 0
  insideSub = 0
  currentSubName$ = ""
  declareCount = 0
  dataItemCount = 0

  initSymbolHash
  initStackLayout

  ff = updateStackAlignment

  gfxConfig.SizeX = 640 ' Defaults if not specified
  gfxConfig.SizeY = 480

  ' Define internal heap pointers early so they get VarBase slots
  internalTempHeapSymbolIdx = 0
  ff = resolveSymbol("!G_MEM_TEMP_HEAP_PTR")
  IF ff = 1 THEN internalTempHeapSymbolIdx = returnedData2

  ff = resolveSymbol("!G_MEM_TEMP_START_PTR")
  ff = resolveSymbol("!G_MEM_PROCESS_HEAP_PTR")
  ff = resolveSymbol("!G_SYS_ERR_HANDLER_PTR")
  ff = resolveSymbol("!G_SYS_SAFE_RSP_PTR")
  ff = resolveSymbol("!G_SYS_LAST_ERR_PTR")

  ff = resolveSymbol("!G_SYS_DATA_PTR_VAL")
  ff = resolveSymbol("!G_SYS_DATA_COUNT_VAL")

  ff = resolveSymbol("!G_GFX_LAST_FG_VAL")
  ff = resolveSymbol("!G_GFX_LAST_BG_VAL")
  ff = resolveSymbol("!G_GFX_COLOR_INIT_FLAG")

  ff = resolveSymbol("!G_SYS_RT_ARG1_VAL")
  ff = resolveSymbol("!G_SYS_RT_ARG2_VAL")
  ff = resolveSymbol("!G_SYS_RT_ARG3_VAL")
  ff = resolveSymbol("!G_SYS_RT_ARG4_VAL")
  ff = resolveSymbol("!G_SYS_RT_ARG5_VAL")

  ff = resolveSymbol("!G_SYS_RT_FARG1_VAL")
  IF ff = 1 THEN symbols(returnedData2).DataType = TYPE_DOUBLE

  ff = resolveSymbol("!G_GFX_PLOT_OFFSET_IDX")
  ff = resolveSymbol("!G_GFX_PLOT_FBBASE_PTR")
  ff = resolveSymbol("!G_GFX_PLOT_TARGET_PTR")

  ff = resolveSymbol("!G_GFX_X1_VAL")
  ff = resolveSymbol("!G_GFX_Y1_VAL")
  ff = resolveSymbol("!G_GFX_X2_VAL")
  ff = resolveSymbol("!G_GFX_Y2_VAL")
  ff = resolveSymbol("!G_GFX_COLOR_VAL")
  ff = resolveSymbol("!G_GFX_BOX_FLAG")
  ff = resolveSymbol("!G_GFX_STYLE_VAL")
  ff = resolveSymbol("!G_GFX_DX_VAL")
  ff = resolveSymbol("!G_GFX_DY_VAL")
  ff = resolveSymbol("!G_GFX_SX_VAL")
  ff = resolveSymbol("!G_GFX_SY_VAL")

  ff = resolveSymbol("!G_GFX_AUTODISPLAY_FLAG")
  ff = resolveSymbol("!G_GFX_DISPLAYI_PENDING_FLAG")
  ff = resolveSymbol("!G_GFX_DISPLAYI_TIMER_VAL")

  ' UI Message Loop Isolation variables
  ff = resolveSymbol("!G_WND_MSG_VAL")
  ff = resolveSymbol("!G_WND_WPARAM_VAL")
  ff = resolveSymbol("!G_WND_LPARAM_VAL")
  ff = resolveSymbol("!G_WND_RET_VAL")
  ff = resolveSymbol("!G_WND_READY_FLAG") ' Spinlock flag for startup synchronization

  ff = resolveSymbol("!G_LAYOUT_GFX_BUF_FRONT_ARR")
  ff = resolveSymbol("!G_LAYOUT_GFX_BUF_BACK_ARR")
  ff = resolveSymbol("!G_LAYOUT_FRAMEBUF_FRONT_ARR")
  ff = resolveSymbol("!G_LAYOUT_FRAMEBUF_BACK_ARR")
  ff = resolveSymbol("!G_GFX_BUF_FRONT_PTR")
  ff = resolveSymbol("!G_GFX_BUF_BACK_PTR")
  ff = resolveSymbol("!G_FRAMEBUF_FRONT_PTR")
  ff = resolveSymbol("!G_FRAMEBUF_BACK_PTR")
  ff = resolveSymbol("!G_GFX_BUF_COUNT_FRONT_VAL")
  ff = resolveSymbol("!G_GFX_BUF_COUNT_BACK_VAL")
  ff = resolveSymbol("!G_WND_RENDER_LOCK_FLAG")

  ff = resolveSymbol("!G_LAYOUT_HWND_VAL")
  ff = resolveSymbol("!G_LAYOUT_WINDOW_W_VAL")
  ff = resolveSymbol("!G_LAYOUT_WINDOW_H_VAL")

  ff = resolveSymbol("!G_LAYOUT_KBD_HEAD_VAL")
  ff = resolveSymbol("!G_LAYOUT_KBD_TAIL_VAL")
  ff = resolveSymbol("!G_LAYOUT_KBD_BUF_ARR")
  ff = resolveSymbol("!G_LAYOUT_KBD_STATE_ARR")

  ff = resolveSymbol("!G_LAYOUT_MOUSE_HEAD_VAL")
  ff = resolveSymbol("!G_LAYOUT_MOUSE_TAIL_VAL")
  ff = resolveSymbol("!G_LAYOUT_MOUSE_BUF_ARR")

  ff = resolveSymbol("!G_IO_MOUSE_X_VAL")
  ff = resolveSymbol("!G_IO_MOUSE_Y_VAL")
  ff = resolveSymbol("!G_IO_MOUSE_B1_VAL")
  ff = resolveSymbol("!G_IO_MOUSE_B2_VAL")
  ff = resolveSymbol("!G_IO_MOUSE_B3_VAL")
  ff = resolveSymbol("!G_IO_MOUSE_SCRL_VAL")

  ff = resolveSymbol("!G_LAYOUT_MEMDC_VAL")
  ff = resolveSymbol("!G_LAYOUT_DIB_PTR_VAL")
  ff = resolveSymbol("!G_LAYOUT_HBITMAP_VAL")

  ff = resolveSymbol("!G_LAYOUT_FILE_HANDLES_ARR")
  ff = resolveSymbol("!G_LAYOUT_DATA_PTR_ARR") ' Relates to handling DATA statements

  ff = resolveSymbol("!G_SYS_EXIT_VAL")
  IF ff = 1 THEN
    vIdxExit = returnedData2
    symbols(vIdxExit).DataType = TYPE_LONG
  END IF

  ff = resolveSymbol("!G_SYS_GOSUB_ARR")
  IF ff = 1 THEN
    vIdxGosub = returnedData2
    symbols(vIdxGosub).DataType = TYPE_INTEGER64
    symbols(vIdxGosub).Size = 256
    symbols(vIdxGosub).IsArray = 1
  END IF

  ff = resolveSymbol("!G_SYS_GOSUB_IDX")

  ' Pre-declare singleton literal strings to guarantee safe isolation in the string pool
  ff = resolveSymbol("!G_IO_FMT_G_DESC$")
  IF ff = 1 THEN
    fmtIdx = returnedData2
    strVarData$(fmtIdx) = "%g"
  END IF

  ff = resolveSymbol("!G_IO_PAUSE_DESC$")
  IF ff = 1 THEN
    pauseStrIdx = returnedData2
    strVarData$(pauseStrIdx) = "Press any key to continue..."
  END IF

  ff = resolveSymbol("!G_IO_CRLF_DESC$")
  IF ff = 1 THEN
    crlfIdx = returnedData2
    strVarData$(crlfIdx) = CHR$(13) + CHR$(10)
  END IF

  ff = resolveSymbol("!G_IO_CLSSCR_DESC$")
  IF ff = 1 THEN
    clsScrIdx = returnedData2
    strVarData$(clsScrIdx) = STRING$(120, 32) + CHR$(13) + CHR$(10)
  END IF

  ff = resolveSymbol("!G_SYS_EMPTY_DESC$")
  IF ff = 1 THEN
    emptyDescIdx = returnedData2
    strVarData$(emptyDescIdx) = ""
  END IF

  t.IsActive = 0 ' Setup complete, clear tira persmission flag

  FOR iy = 1 TO COMPILE_LINE_MAX
    compileText$(iy) = ""
    editorLineLinkMap(iy) = 0
  NEXT

  compileText$(0) = "LINE 0: YOU SHOULD NEVER SEE THIS"
  editorLineLinkMap(0) = 0

  compilePass1LexiConsts

  DO
    ff = compilePass2Flatten
  LOOP WHILE ff = 1 ' 1 indicates more work needs to be done

  ff = resolveSymbol("!G_GFX_PALETTE_DESC$")
  IF ff = 1 THEN
    gfxPalIdx = returnedData2
    palStr$ = ""
    FOR ii = 0 TO 255
      palStr$ = palStr$ + CHR$(outputPal(ii, palBLUE))
      palStr$ = palStr$ + CHR$(outputPal(ii, palGREEN))
      palStr$ = palStr$ + CHR$(outputPal(ii, palRED))
      palStr$ = palStr$ + CHR$(0)
    NEXT
    strVarData$(gfxPalIdx) = palStr$
  END IF

  ff = resolveSymbol("!G_GFX_FG_VAL")
  ff = resolveSymbol("!G_GFX_CUR_X_VAL")
  ff = resolveSymbol("!G_GFX_CUR_Y_VAL")

  compilePass3Scan

  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    EXIT FUNCTION
  END IF

  ' Register Window literals safely after directives are scanned
  ff = resolveSymbol("!G_WND_CLASS_DESC$")
  IF ff = 1 THEN
    clsIdx = returnedData2
    strVarData$(clsIdx) = "DefaultClass"
  END IF

  ff = resolveSymbol("!G_WND_TITLE_DESC$")
  IF ff = 1 THEN
    winIdx = returnedData2
    strVarData$(winIdx) = compileWindowTitle$
  END IF

  ff = resolveSymbol("!G_GFX_FONT_DESC$")
  IF ff = 1 THEN
    fntIdx = returnedData2
    strVarData$(fntIdx) = "Terminal"
  END IF

  compilePass4Symbols

  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    EXIT FUNCTION
  END IF

  compile = 1

END FUNCTION ' compile

''''''''''''''''''''''''
'''' CODE IS IDENTICAL UP TO THIS POINT - THIS IS NEWER VERSION

''''''''''''''''''''''''
SUB compilePass1LexiConsts

  ' Pass 1: Performs a double sweep to register and evaluate all CONST declarations
  ' Replaces all constant names with literal values throughout the source file
  ' Fully expanded lines are written to the compileText$ array for pass 2

  DIM stripLen AS LONG
  DIM eqPos AS LONG
  DIM inQuotes AS LONG
  DIM valLen AS LONG
  DIM isIdentStart AS LONG
  DIM isMatchFound AS LONG
  DIM matchedIdx AS LONG
  DIM inQ AS LONG
  DIM exLen AS LONG
  DIM lineLen AS LONG
  DIM preventExpansion AS LONG
  DIM prevIx AS LONG
  DIM inTypeBlock AS LONG
  DIM firstWordFound AS LONG
  DIM isRem AS LONG
  DIM isDir AS LONG

  textConstCount = 0

  ' This loop exists to perform the first sweep over every line of code in the editor
  ' The goal of this specific loop is strictly to find CONST declarations and harvest their values
  FOR iy = 1 TO editor.LastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    currentLineNumber = iy
    curLine$ = editorText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    ff$ = retLabelStripLength$(tempLine$)
    stripLen = returnedData2

    rawNoLabel$ = tempLine$
    IF stripLen > 0 THEN
      rawNoLabel$ = LTRIM$(MID$(tempLine$, stripLen + 1))
    END IF

    ' Check the first six characters of the cleaned line to see if it says CONST
    IF UCASE$(LEFT$(rawNoLabel$, 6)) = "CONST " THEN
      remLine$ = LTRIM$(MID$(rawNoLabel$, 7))
      eqPos = INSTR(remLine$, "=")
      IF eqPos > 0 THEN
        cName$ = UCASE$(LTRIM$(RTRIM$(LEFT$(remLine$, eqPos - 1))))

        cSuffix$ = RIGHT$(cName$, 1)
        IF cSuffix$ = "$" OR cSuffix$ = "#" OR cSuffix$ = "!" OR cSuffix$ = "%" OR cSuffix$ = "&" THEN
          throwCompilerError "CONSTANTS CANNOT HAVE TYPE SUFFIXES", ASIS, 0
          EXIT SUB
        END IF

        cValRaw$ = LTRIM$(RTRIM$(MID$(remLine$, eqPos + 1)))

        ' We check the existing array of harvested constants to ensure the user is not trying to define the same constant twice
        FOR iConst = 0 TO textConstCount - 1
          IF UCASE$(textConsts(iConst).Name) = cName$ THEN
            throwCompilerError "CONSTANT ALREADY DEFINED", ASIS, 0
            EXIT SUB
          END IF
        NEXT

        expandedVal$ = ""
        inQuotes = 0
        valLen = LEN(cValRaw$)
        ix = 1

        ' This loop exists to read the right side of the equals sign character by character
        ' This is because a constant might be defined using another constant, like CONST B = A * 2
        ' We have to identify those nested constant names and swap them with their literal values before doing the math
        DO WHILE ix <= valLen
          ch$ = MID$(cValRaw$, ix, 1)

          IF ch$ = CHR$(34) THEN
            inQuotes = 1 - inQuotes
            expandedVal$ = expandedVal$ + ch$
            ix = ix + 1
          ELSE
            IF inQuotes = 0 AND ch$ = "'" THEN
              expandedVal$ = expandedVal$ + MID$(cValRaw$, ix)
              EXIT DO
            ELSE
              isIdentStart = 0
              uCh$ = UCASE$(ch$)
              IF (uCh$ >= "A" AND uCh$ <= "Z") OR uCh$ = "_" THEN isIdentStart = 1

              IF inQuotes = 0 AND isIdentStart = 1 THEN

                ' Backscan to protect UDT fields, Hex prefixes, and Directives from being mutated
                preventExpansion = 0
                prevIx = ix - 1
                DO WHILE prevIx > 0
                  prevCh$ = MID$(cValRaw$, prevIx, 1)
                  IF prevCh$ = " " OR prevCh$ = CHR$(9) THEN
                    prevIx = prevIx - 1
                  ELSE
                    IF prevCh$ = "." OR prevCh$ = "&" OR prevCh$ = "#" OR prevCh$ = "$" OR prevCh$ = "%" OR prevCh$ = "!" OR prevCh$ = "~" THEN preventExpansion = 1
                    EXIT DO
                  END IF
                LOOP

                ident$ = ""
                DO WHILE ix <= valLen
                  ch2$ = MID$(cValRaw$, ix, 1)
                  u2$ = UCASE$(ch2$)
                  IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") OR u2$ = "_" THEN
                    ident$ = ident$ + ch2$
                    ix = ix + 1
                  ELSE
                    EXIT DO
                  END IF
                LOOP

                IF ix <= valLen THEN
                  chCheckSuffix$ = MID$(cValRaw$, ix, 1)
                  IF chCheckSuffix$ = "$" OR chCheckSuffix$ = "#" OR chCheckSuffix$ = "!" OR chCheckSuffix$ = "%" OR chCheckSuffix$ = "&" THEN
                    ident$ = ident$ + chCheckSuffix$
                    ix = ix + 1
                  END IF
                END IF

                isMatchFound = 0
                matchedIdx = 0
                searchIdent$ = UCASE$(ident$)

                IF searchIdent$ = "REM" THEN
                  isRem = 0
                  IF ix - LEN(ident$) = 1 THEN
                    isRem = 1
                  ELSE
                    prevCh$ = MID$(cValRaw$, ix - LEN(ident$) - 1, 1)
                    IF prevCh$ = " " OR prevCh$ = CHR$(9) OR prevCh$ = ":" THEN isRem = 1
                  END IF
                  IF isRem = 1 THEN
                    expandedVal$ = expandedVal$ + "'" + MID$(cValRaw$, ix)
                    EXIT DO
                  END IF
                END IF

                ' Only check dictionary if we are safe from structural collisions
                IF preventExpansion = 0 THEN
                  FOR iConst = 0 TO textConstCount - 1
                    IF UCASE$(textConsts(iConst).Name) = searchIdent$ THEN
                      matchedIdx = iConst
                      isMatchFound = 1
                      EXIT FOR
                    END IF
                  NEXT
                END IF

                IF isMatchFound = 1 THEN
                  expandedVal$ = expandedVal$ + textConsts(matchedIdx).Value
                ELSE
                  expandedVal$ = expandedVal$ + ident$
                END IF
              ELSE
                expandedVal$ = expandedVal$ + ch$
                ix = ix + 1
              END IF
            END IF
          END IF
        LOOP

        inQ = 0
        exLen = LEN(expandedVal$)
        cValClean$ = ""

        ' Strips out any inline comments from the right side of the constant declaration
        ' We do this because passing comments into the math evaluator will break the math resolution
        FOR iv = 1 TO exLen
          cv$ = MID$(expandedVal$, iv, 1)
          IF cv$ = CHR$(34) THEN inQ = 1 - inQ
          IF inQ = 0 THEN
            IF cv$ = "'" THEN EXIT FOR
            IF iv <= exLen - 2 THEN
              IF UCASE$(MID$(expandedVal$, iv, 3)) = "REM" THEN
                isRem = 0
                IF iv = 1 THEN
                  isRem = 1
                ELSE
                  prevCh$ = MID$(expandedVal$, iv - 1, 1)
                  IF prevCh$ = " " OR prevCh$ = CHR$(9) OR prevCh$ = ":" THEN isRem = 1
                END IF
                IF isRem = 1 THEN
                  IF iv + 3 > exLen THEN
                    EXIT FOR
                  ELSE
                    nextCh$ = MID$(expandedVal$, iv + 3, 1)
                    IF nextCh$ = " " OR nextCh$ = CHR$(9) THEN EXIT FOR
                  END IF
                END IF
              END IF
            END IF
          END IF
          cValClean$ = cValClean$ + cv$
        NEXT
        cValClean$ = LTRIM$(RTRIM$(cValClean$))

        ' Pass the cleaned string into the math evaluator so things like 10 * 2 become 20
        cValClean$ = evalMathConst$(cValClean$)

        IF textConstCount < MAX_TEXT_CONSTS THEN
          textConsts(textConstCount).Name = cName$
          textConsts(textConstCount).Value = cValClean$
          textConstCount = textConstCount + 1
        END IF
      END IF
    END IF
  NEXT

  ' Second sweep over every line of code, swaps out the constant names with the literal values we harvested in the first sweep
  inTypeBlock = 0

  FOR iy = 1 TO editor.LastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    currentLineNumber = iy
    curLine$ = editorText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    ff$ = retLabelStripLength$(tempLine$)
    stripLen = returnedData2

    rawNoLabel$ = tempLine$
    IF stripLen > 0 THEN
      rawNoLabel$ = LTRIM$(MID$(tempLine$, stripLen + 1))
    END IF

    ' End Type tracking must evaluate before we parse the current line's text
    IF UCASE$(LEFT$(rawNoLabel$, 8)) = "END TYPE" THEN
      inTypeBlock = 0
    END IF

    ' We check for CONST here so we can erase the entire line from the compileText$ array
    ' We do this because the constants are already harvested and we do not want the compiler trying to parse them as regular code
    IF UCASE$(LEFT$(rawNoLabel$, 6)) = "CONST " THEN
      compileText$(iy) = ""
    ELSE
      firstWordFound = 0
      inQuotes = 0
      expandedLine$ = ""
      lineLen = LEN(curLine$)
      ix = 1

      ' Read the active code line character by character to identify words that might be constant names without accidentally replacing text inside of strings
      DO WHILE ix <= lineLen
        ch$ = MID$(curLine$, ix, 1)

        IF ch$ = CHR$(34) THEN
          inQuotes = 1 - inQuotes
          expandedLine$ = expandedLine$ + ch$
          ix = ix + 1
        ELSE
          IF inQuotes = 0 AND ch$ = "'" THEN
            isDir = 0
            checkDir$ = LTRIM$(MID$(curLine$, ix + 1))
            IF LEFT$(checkDir$, 1) = "#" THEN
              dirWord$ = ""
              FOR id = 1 TO LEN(checkDir$)
                chCheck$ = MID$(checkDir$, id, 1)
                IF chCheck$ = " " OR chCheck$ = CHR$(9) THEN EXIT FOR
                dirWord$ = dirWord$ + UCASE$(chCheck$)
              NEXT
              IF dirWord$ = "#CLASSIC" OR dirWord$ = "#STRINGSTRICT" OR dirWord$ = "#GRAPHICS" OR dirWord$ = "#GDOUBLE" OR dirWord$ = "#DEFINT" OR dirWord$ = "#EMERALD" THEN
                isDir = 1
              END IF
            END IF

            IF isDir = 0 THEN
              expandedLine$ = expandedLine$ + MID$(curLine$, ix)
              EXIT DO
            ELSE
              expandedLine$ = expandedLine$ + ch$
              ix = ix + 1
            END IF
          ELSE
            isIdentStart = 0
            uCh$ = UCASE$(ch$)
            IF (uCh$ >= "A" AND uCh$ <= "Z") OR uCh$ = "_" THEN isIdentStart = 1

            IF inQuotes = 0 AND isIdentStart = 1 THEN

              ' Backscan to protect UDT fields, Hex prefixes, and Directives from being mutated
              preventExpansion = 0
              prevIx = ix - 1
              DO WHILE prevIx > 0
                prevCh$ = MID$(curLine$, prevIx, 1)
                IF prevCh$ = " " OR prevCh$ = CHR$(9) THEN
                  prevIx = prevIx - 1
                ELSE
                  IF prevCh$ = "." OR prevCh$ = "&" OR prevCh$ = "#" OR prevCh$ = "$" OR prevCh$ = "%" OR prevCh$ = "!" OR prevCh$ = "~" THEN preventExpansion = 1
                  EXIT DO
                END IF
              LOOP

              ' Type Block Protection: Prevents UDT field declarations from being mutated
              IF inTypeBlock = 1 AND firstWordFound = 0 THEN
                preventExpansion = 1
              END IF

              ident$ = ""
              DO WHILE ix <= lineLen
                ch2$ = MID$(curLine$, ix, 1)
                u2$ = UCASE$(ch2$)
                IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") OR u2$ = "_" THEN
                  ident$ = ident$ + ch2$
                  ix = ix + 1
                ELSE
                  EXIT DO
                END IF
              LOOP

              IF ix <= lineLen THEN
                chCheckSuffix$ = MID$(curLine$, ix, 1)
                IF chCheckSuffix$ = "$" OR chCheckSuffix$ = "#" OR chCheckSuffix$ = "!" OR chCheckSuffix$ = "%" OR chCheckSuffix$ = "&" THEN
                  ident$ = ident$ + chCheckSuffix$
                  ix = ix + 1
                END IF
              END IF

              isMatchFound = 0
              matchedIdx = 0
              searchIdent$ = UCASE$(ident$)

              ' Intercept REM to prevent any constant replacements from corrupting the comment unless it's a directive
              IF searchIdent$ = "REM" THEN
                isRem = 0
                IF ix - LEN(ident$) = 1 THEN
                  isRem = 1
                ELSE
                  prevCh$ = MID$(curLine$, ix - LEN(ident$) - 1, 1)
                  IF prevCh$ = " " OR prevCh$ = CHR$(9) OR prevCh$ = ":" THEN isRem = 1
                END IF
                IF isRem = 1 THEN
                  isDir = 0
                  checkDir$ = LTRIM$(MID$(curLine$, ix))
                  IF LEFT$(checkDir$, 1) = "#" THEN
                    dirWord$ = ""
                    FOR id = 1 TO LEN(checkDir$)
                      chCheck$ = MID$(checkDir$, id, 1)
                      IF chCheck$ = " " OR chCheck$ = CHR$(9) THEN EXIT FOR
                      dirWord$ = dirWord$ + UCASE$(chCheck$)
                    NEXT
                    IF dirWord$ = "#CLASSIC" OR dirWord$ = "#STRINGSTRICT" OR dirWord$ = "#GRAPHICS" OR dirWord$ = "#GDOUBLE" OR dirWord$ = "#DEFINT" OR dirWord$ = "#EMERALD" THEN
                      isDir = 1
                    END IF
                  END IF

                  IF isDir = 0 THEN
                    expandedLine$ = expandedLine$ + "'" + MID$(curLine$, ix)
                    EXIT DO
                  ELSE
                    expandedLine$ = expandedLine$ + "REM"
                    firstWordFound = 1
                    preventExpansion = 1 ' Protect the word REM itself, but let loop keep going
                  END IF
                END IF
              END IF

              ' Check the harvested constants array to see if the word we just isolated is a known constant
              IF preventExpansion = 0 THEN
                FOR iConst = 0 TO textConstCount - 1
                  IF UCASE$(textConsts(iConst).Name) = searchIdent$ THEN
                    matchedIdx = iConst
                    isMatchFound = 1
                    EXIT FOR
                  END IF
                NEXT
              END IF

              ' If a match is found, append the literal value into the line buffer instead of the name
              IF isMatchFound = 1 THEN
                expandedLine$ = expandedLine$ + textConsts(matchedIdx).Value
              ELSE
                IF searchIdent$ <> "REM" THEN expandedLine$ = expandedLine$ + ident$
              END IF

              firstWordFound = 1
            ELSE
              expandedLine$ = expandedLine$ + ch$
              ix = ix + 1
            END IF
          END IF
        END IF
      LOOP

      compileText$(iy) = expandedLine$
    END IF

    ' Begin Type tracking must trigger AFTER processing the line, so the word "TYPE" itself is not protected
    IF UCASE$(LEFT$(rawNoLabel$, 5)) = "TYPE " THEN
      inTypeBlock = 1
    END IF
  NEXT

  ' Establish the 1:1 line mapping baseline before flatting is introduced
  compileLastLine = editor.LastLine
  FOR iy = 1 TO compileLastLine
    editorLineLinkMap(iy) = iy
  NEXT

  currentLineNumber = 1

END SUB ' compilePass1LexiConsts

''''''''''''''''''''''''
FUNCTION compilePass2Flatten

  DIM outCount AS LONG
  DIM origLineMap AS LONG
  DIM stripLen AS LONG
  DIM isSingleLineIf AS LONG
  DIM hasElse AS LONG
  DIM elseIdx AS LONG
  DIM thenIdx AS LONG
  DIM parenDepth AS LONG
  DIM ifDepth AS LONG
  DIM endThen AS LONG
  DIM needsExtraPass AS LONG

  ' Variables for inline flattening
  DIM rangeStart(2) AS LONG
  DIM rangeEnd(2) AS LONG
  DIM rangeCount AS LONG
  DIM flattenStart AS LONG
  DIM flattenEnd AS LONG
  DIM chunkStart AS LONG
  DIM tVal AS LONG
  DIM tVal2 AS LONG
  DIM hasIf AS LONG
  DIM thenPos AS LONG
  DIM ignoreColon AS LONG

  DIM tempText$(COMPILE_LINE_MAX)
  DIM tempMap(COMPILE_LINE_MAX) AS LONG

  DIM inQuotes AS LONG
  DIM commentPos AS LONG
  DIM ix AS LONG
  DIM hasDirectiveComment AS LONG

  outCount = 0
  needsExtraPass = 0

  FOR iy = 1 TO compileLastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      EXIT FUNCTION
    END IF

    curLine$ = compileText$(iy)
    origLineMap = editorLineLinkMap(iy)

    tempLine$ = LTRIM$(RTRIM$(curLine$))

    IF tempLine$ <> "" THEN
      ' Isolate Labels so we don't accidentally split code connected to them
      labelStr$ = retLabelStripLength$(tempLine$)
      stripLen = returnedData2

      IF stripLen > 0 THEN
        outCount = outCount + 1
        tempText$(outCount) = labelStr$ + ":"
        tempMap(outCount) = origLineMap
        tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
        IF tempLine$ <> "" THEN needsExtraPass = 1 ' A label obscuring a command triggers an extra pass
      END IF

      hasDirectiveComment = 0
      remText$ = ""

      IF tempLine$ <> "" THEN
        inQuotes = 0
        commentPos = 0
        FOR ix = 1 TO LEN(tempLine$)
          chCheck$ = MID$(tempLine$, ix, 1)
          IF chCheck$ = CHR$(34) THEN inQuotes = 1 - inQuotes
          IF inQuotes = 0 AND chCheck$ = "'" THEN
            commentPos = ix
            EXIT FOR
          END IF
        NEXT

        IF commentPos > 0 THEN
          remText$ = MID$(tempLine$, commentPos)
          checkDir$ = LTRIM$(MID$(tempLine$, commentPos + 1))
          IF LEFT$(checkDir$, 1) = "#" THEN
            dirWord$ = ""
            FOR ix = 1 TO LEN(checkDir$)
              chCheck$ = MID$(checkDir$, ix, 1)
              IF chCheck$ = " " OR chCheck$ = CHR$(9) THEN EXIT FOR
              dirWord$ = dirWord$ + UCASE$(chCheck$)
            NEXT
            IF dirWord$ = "#CLASSIC" OR dirWord$ = "#STRINGSTRICT" OR dirWord$ = "#GRAPHICS" OR dirWord$ = "#GDOUBLE" OR dirWord$ = "#DEFINT" OR dirWord$ = "#EMERALD" THEN
              hasDirectiveComment = 1
            END IF
          END IF
        END IF
      END IF

      IF tempLine$ <> "" THEN
        tokenizeLine tempLine$
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
          EXIT FUNCTION
        END IF

        IF lineTokenCount > 0 THEN
          isSingleLineIf = 0
          hasElse = 0
          elseIdx = 0
          thenIdx = 0

          IF lineTokenVals(0) = TOK_IF THEN
            FOR iTok = 1 TO lineTokenCount - 1
              IF lineTokenVals(iTok) = TOK_THEN THEN
                thenIdx = iTok
                IF iTok < lineTokenCount - 1 THEN
                  isSingleLineIf = 1
                END IF
                EXIT FOR
              END IF
            NEXT

            IF isSingleLineIf = 1 THEN
              parenDepth = 0
              ifDepth = 0
              FOR iTok = thenIdx + 1 TO lineTokenCount - 1
                tVal = lineTokenVals(iTok)
                IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
                IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1
                IF parenDepth = 0 THEN
                  IF tVal = TOK_IF THEN ifDepth = ifDepth + 1
                  IF tVal = TOK_ELSE THEN
                    IF ifDepth = 0 THEN
                      hasElse = 1
                      elseIdx = iTok
                      EXIT FOR
                    ELSE
                      ifDepth = ifDepth - 1
                    END IF
                  END IF
                END IF
              NEXT
            END IF
          END IF

          rangeCount = 0

          IF isSingleLineIf = 1 THEN
            outCount = outCount + 1
            tempText$(outCount) = flattenRebuildStr$(0, thenIdx)
            tempMap(outCount) = origLineMap

            endThen = lineTokenCount - 1
            IF hasElse = 1 THEN endThen = elseIdx - 1

            ' Enqueue THEN branch
            rangeStart(rangeCount) = thenIdx + 1
            rangeEnd(rangeCount) = endThen
            rangeCount = rangeCount + 1

            IF hasElse = 1 THEN
              ' Enqueue ELSE branch
              rangeStart(rangeCount) = elseIdx + 1
              rangeEnd(rangeCount) = lineTokenCount - 1
              rangeCount = rangeCount + 1
            END IF
          ELSE
            ' Enqueue regular statement
            rangeStart(rangeCount) = 0
            rangeEnd(rangeCount) = lineTokenCount - 1
            rangeCount = rangeCount + 1
          END IF

          ' Iterate over the enqueued ranges sequentially
          FOR iRange = 0 TO rangeCount - 1
            flattenStart = rangeStart(iRange)
            flattenEnd = rangeEnd(iRange)

            chunkStart = flattenStart
            parenDepth = 0

            FOR ii = flattenStart TO flattenEnd
              tVal = lineTokenVals(ii)
              IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
              IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1

              IF parenDepth = 0 AND tVal = 256 + ASC(":") THEN
                ignoreColon = 0
                IF ii = chunkStart + 1 THEN
                  IF lineTokenVals(chunkStart) = TOK_CASE THEN
                    ignoreColon = 1
                  END IF
                END IF

                IF ignoreColon = 0 THEN
                  IF ii > chunkStart THEN
                    outCount = outCount + 1
                    tempText$(outCount) = flattenRebuildStr$(chunkStart, ii - 1)
                    tempMap(outCount) = origLineMap

                    ' Targeted evaluation: Only trigger an extra pass if the chunk we just split contains a nested single-line IF
                    hasIf = 0
                    thenPos = 0
                    FOR jj = chunkStart TO ii - 1
                      tVal2 = lineTokenVals(jj)
                      IF tVal2 = TOK_IF THEN hasIf = 1
                      IF tVal2 = TOK_THEN THEN thenPos = jj
                    NEXT
                    IF hasIf = 1 AND thenPos > 0 AND thenPos < ii - 1 THEN needsExtraPass = 1
                  END IF
                  chunkStart = ii + 1
                END IF
              END IF
            NEXT

            IF chunkStart <= flattenEnd THEN
              outCount = outCount + 1
              tempText$(outCount) = flattenRebuildStr$(chunkStart, flattenEnd)
              tempMap(outCount) = origLineMap

              hasIf = 0
              thenPos = 0
              FOR jj = chunkStart TO flattenEnd
                tVal2 = lineTokenVals(jj)
                IF tVal2 = TOK_IF THEN hasIf = 1
                IF tVal2 = TOK_THEN THEN thenPos = jj
              NEXT
              IF hasIf = 1 AND thenPos > 0 AND thenPos < flattenEnd THEN needsExtraPass = 1
            END IF

            ' Handle intermediate insertions for single line IF ELSE statements
            IF isSingleLineIf = 1 THEN
              IF hasElse = 1 THEN
                IF iRange = 0 THEN
                  outCount = outCount + 1
                  tempText$(outCount) = "ELSE"
                  tempMap(outCount) = origLineMap
                END IF
              END IF
            END IF
          NEXT iRange

          ' Append trailing END IF if necessary
          IF isSingleLineIf = 1 THEN
            outCount = outCount + 1
            tempText$(outCount) = "END IF"
            tempMap(outCount) = origLineMap
          END IF
        END IF

        IF hasDirectiveComment = 1 THEN
          outCount = outCount + 1
          tempText$(outCount) = remText$
          tempMap(outCount) = origLineMap
        END IF
      END IF
    END IF
  NEXT

  compileLastLine = outCount
  FOR iy = 1 TO compileLastLine
    compileText$(iy) = tempText$(iy)
    editorLineLinkMap(iy) = tempMap(iy)
  NEXT

  compilePass2Flatten = needsExtraPass

END FUNCTION ' compilePass2Flatten

''''''''''''''''''''''''
SUB compilePass3Scan

  ' Pass 3: Scans for compiler directives and handles label stripping
  ' Validates that directives like #GRAPHICS or #DEFINT appear before any code
  ' Logs warnings for unsupported legacy QBasic screen and display commands
  ' Now evaluates standard DEFINT commands globally here to prepare defIntMap before Symbol Resolution Pass 4

  DIM firstCodeLineFound AS LONG
  DIM stripLen AS LONG
  DIM tVal AS LONG
  DIM tokIdx AS LONG
  DIM char1 AS LONG
  DIM char2 AS LONG

  DIM ix AS LONG

  firstCodeLineFound = 0
  defaultArrayDynamic = 0

  FOR iy = 1 TO compileLastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    currentLineNumber = editorLineLinkMap(iy)
    curLine$ = compileText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    IF LEN(tempLine$) > 0 THEN
      ff$ = retLabelStripLength$(tempLine$)
      stripLen = returnedData2

      IF stripLen > 0 THEN
        tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
      END IF

      IF LEFT$(tempLine$, 1) = "'" THEN
        checkDir$ = LTRIM$(MID$(tempLine$, 2))
        IF LEFT$(checkDir$, 1) = "#" THEN
          dirWord$ = ""
          FOR ix = 1 TO LEN(checkDir$)
            chCheck$ = MID$(checkDir$, ix, 1)
            IF chCheck$ = " " OR chCheck$ = CHR$(9) THEN EXIT FOR
            dirWord$ = dirWord$ + UCASE$(chCheck$)
          NEXT
          IF dirWord$ = "#CLASSIC" OR dirWord$ = "#STRINGSTRICT" OR dirWord$ = "#GRAPHICS" OR dirWord$ = "#GDOUBLE" OR dirWord$ = "#DEFINT" OR dirWord$ = "#EMERALD" THEN
            IF firstCodeLineFound = 1 THEN
              addStatusMsg "WARNING line " + retLineNumberStr$ + ": DIRECTIVE IN COMMENT AFTER CODE IGNORED"
            ELSE
              tempLine$ = checkDir$
            END IF
          END IF
        END IF
      END IF

      IF LEN(tempLine$) > 0 THEN
        tokenizeLine tempLine$
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

        IF lineTokenCount > 0 THEN
          FOR iTok = 0 TO lineTokenCount - 1
            tVal = lineTokenVals(iTok)

            SELECT CASE tVal

              CASE TOK_SCREEN, TOK_FONT, TOK_LIMIT
                warnStr$ = retTokenText$(lineTokens$(iTok))
                IF warnStr$ = "" THEN warnStr$ = "UNKNOWN"
                addStatusMsg "WARNING line " + retLineNumberStr$ + ": " + warnStr$ + " UNSUPPORTED, LINE IGNORED"

            END SELECT ' tVal

          NEXT

          firstTok$ = lineTokens$(0)
          tVal = lineTokenVals(0)

          SELECT CASE tVal

            CASE TOK_GRAPHICS, TOK_GDOUBLE, TOK_DEFINT, TOK_CLASSIC, TOK_DEFINT_NORM, TOK_STRINGSTRICT, TOK_EMERALD
              IF tVal <> TOK_DEFINT_NORM THEN
                IF firstCodeLineFound = 1 THEN
                  throwCompilerError "DIRECTIVES MUST COME BEFORE CODE", ASIS, 0
                  EXIT SUB
                END IF
              ELSE
                IF compileHasGlobalDefInt = 1 THEN
                  throwCompilerError "CANNOT USE DEFINT WHEN #DEFINT IS ACTIVE", ASIS, 0
                  EXIT SUB
                END IF
                firstCodeLineFound = 1
              END IF

              SELECT CASE tVal

                CASE TOK_CLASSIC
                  compileClassicMode = 1

                CASE TOK_EMERALD
                  compileEmeraldMode = 1
                  compileStringStrict = 1

                CASE TOK_STRINGSTRICT
                  compileStringStrict = 1

                CASE TOK_GRAPHICS
                  compileHasGraphics = 1
                  tokIdx = 1
                  IF tokIdx < lineTokenCount THEN
                    gTok$ = lineTokens$(tokIdx)
                    IF LEFT$(gTok$, 1) >= "0" AND LEFT$(gTok$, 1) <= "9" THEN
                      gfxConfig.SizeX = VAL(gTok$)
                      IF gfxConfig.SizeX < 64 OR gfxConfig.SizeX > FRAMEBUF_MAX_WIDTH THEN
                        throwCompilerError "X MUST BE 64 TO 1024", ASIS, 0
                        EXIT SUB
                      END IF
                      tokIdx = tokIdx + 1

                      IF tokIdx < lineTokenCount THEN
                        IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
                          tokIdx = tokIdx + 1
                        END IF
                      END IF

                      IF tokIdx < lineTokenCount THEN
                        gTok$ = lineTokens$(tokIdx)
                        IF LEFT$(gTok$, 1) >= "0" AND LEFT$(gTok$, 1) <= "9" THEN
                          gfxConfig.SizeY = VAL(gTok$)
                          IF gfxConfig.SizeY < 64 OR gfxConfig.SizeY > FRAMEBUF_MAX_HEIGHT THEN
                            throwCompilerError "Y MUST BE 64 TO 1080", ASIS, 0
                            EXIT SUB
                          END IF
                          tokIdx = tokIdx + 1
                        END IF
                      END IF

                      IF tokIdx < lineTokenCount THEN
                        IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
                          tokIdx = tokIdx + 1
                        END IF
                      END IF
                    END IF
                  END IF
                  IF tokIdx < lineTokenCount THEN
                    gTok$ = lineTokens$(tokIdx)
                    IF LEFT$(gTok$, 1) = CHR$(34) THEN
                      compileWindowTitle$ = extractQuotes$(gTok$)
                    END IF
                  END IF

                CASE TOK_GDOUBLE
                  compileGraphicsDouble = 1

                CASE TOK_DEFINT, TOK_DEFINT_NORM
                  IF tVal = TOK_DEFINT THEN compileHasGlobalDefInt = 1
                  tokIdx = 1
                  DO WHILE tokIdx < lineTokenCount
                    tok$ = lineTokens$(tokIdx)
                    IF LEN(tok$) <> 1 THEN
                      throwCompilerError "EXPECTED LETTER", ASIS, 0
                      EXIT SUB
                    END IF
                    char1 = ASC(UCASE$(tok$))
                    IF char1 < 65 OR char1 > 90 THEN
                      throwCompilerError "EXPECTED LETTER A-Z", ASIS, 0
                      EXIT SUB
                    END IF
                    char2 = char1
                    tokIdx = tokIdx + 1
                    IF tokIdx < lineTokenCount THEN
                      IF lineTokenVals(tokIdx) = 256 + ASC("-") THEN
                        tokIdx = tokIdx + 1
                        IF tokIdx < lineTokenCount THEN
                          tok2$ = lineTokens$(tokIdx)
                          IF LEN(tok2$) <> 1 THEN
                            throwCompilerError "EXPECTED LETTER", ASIS, 0
                            EXIT SUB
                          END IF

                          char2 = ASC(UCASE$(tok2$))
                          IF char2 < 65 OR char2 > 90 OR char2 < char1 THEN
                            throwCompilerError "INVALID RANGE", ASIS, 0
                            EXIT SUB
                          END IF
                          tokIdx = tokIdx + 1
                        ELSE
                          throwCompilerError "EXPECTED LETTER AFTER -", ASIS, 0
                          EXIT SUB
                        END IF
                      END IF
                    END IF
                    FOR ix = char1 TO char2
                      defIntMap(ix - 65) = 1
                    NEXT
                    IF tokIdx < lineTokenCount THEN
                      IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
                        tokIdx = tokIdx + 1
                      ELSE
                        throwCompilerError "EXPECTED COMMA", ASIS, 0
                        EXIT SUB
                      END IF
                    END IF
                  LOOP

              END SELECT ' tVal

            CASE TOK_REM
              ' Ignore comment lines so they do not falsely flag as the first line of code

            CASE ELSE
              firstCodeLineFound = 1

          END SELECT ' tVal

        END IF
      END IF
    END IF
  NEXT

  currentLineNumber = 1

END SUB ' compilePass3Scan

''''''''''''''''''''''''
SUB compilePass4Symbols

  ' Pass 4: Discovers and registers all symbols (Labels, Subs, Functions, UDTs, Declares)
  ' Validates matching signatures between DECLARE statements and actual subroutine definitions
  ' Builds the scope mapping and structure offsets for complex data types

  DIM inTypeBlock AS LONG
  DIM currentUdtIdx AS LONG
  DIM stripLen AS LONG
  DIM isNum AS LONG
  DIM numVal AS LONG
  DIM vIdx AS LONG
  DIM tVal AS LONG
  DIM isUdtLine AS LONG
  DIM tVal2 AS LONG
  DIM dRetType AS LONG
  DIM charIdx AS LONG
  DIM tokIdx AS LONG
  DIM aType AS LONG
  DIM aArray AS LONG
  DIM fieldSize AS LONG
  DIM fieldType AS LONG
  DIM fIdx AS LONG
  DIM nameIdx AS LONG
  DIM vIdxArg AS LONG
  DIM subIdx AS LONG
  DIM retVarIdx AS LONG
  DIM argVarIdx AS LONG
  DIM tempUdtIndex AS LONG
  DIM tempIsDynamicString AS LONG
  DIM dtMapped AS LONG
  DIM fixedLen AS LONG
  DIM typeData AS LONG

  inTypeBlock = 0
  currentUdtIdx = 0
  udtCount = 0 ' Initialize the global UDT counter
  defaultArrayDynamic = 0

  FOR iy = 1 TO compileLastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    currentLineNumber = editorLineLinkMap(iy)
    curLine$ = compileText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    IF LEN(tempLine$) > 0 THEN
      labelStr$ = retLabelStripLength$(tempLine$)
      stripLen = returnedData2

      IF stripLen > 0 THEN
        labelName$ = UCASE$(labelStr$)

        isNum = 1
        FOR iCheck = 1 TO LEN(labelName$)
          chCheck$ = MID$(labelName$, iCheck, 1)
          IF chCheck$ < "0" OR chCheck$ > "9" THEN
            isNum = 0
            EXIT FOR
          END IF
        NEXT

        IF isNum = 1 THEN
          IF currentScopeID > 0 THEN
            throwCompilerError "NUMERIC LABELS NOT ALLOWED IN SUB OR FUNCTION", ASIS, 0
            EXIT SUB
          END IF

          numVal = VAL(labelName$)

          IF numVal = 0 THEN
            throwCompilerError "NUMERIC LABEL 0 IS NOT ALLOWED", ASIS, 0
            EXIT SUB
          END IF

          IF numVal <= lastNumericLabel THEN
            throwCompilerError "NUMERIC LABEL " + LTRIM$(RTRIM$(STR$(numVal))) + " FOUND AFTER " + LTRIM$(RTRIM$(STR$(lastNumericLabel))), ASIS, 0
            EXIT SUB
          END IF
          lastNumericLabel = numVal
        END IF

        ' Unconditionally prefix ALL user labels with % to isolate them from variable namespaces
        labelName$ = "%" + labelName$

        ff = resolveSymbol(labelName$)
        IF ff = 0 THEN EXIT SUB
        vIdx = returnedData2

        IF symbols(vIdx).alreadyParsed = 1 THEN
          throwCompilerError "DUPLICATE LABEL " + labelStr$, ASIS, 0
          EXIT SUB
        END IF

        symbols(vIdx).DataType = TYPE_LABEL
        symbols(vIdx).Offset = -1
        symbols(vIdx).IsExplicit = 1
        symbols(vIdx).alreadyParsed = 1
        symbols(vIdx).DataIndex = dataItemCount

        tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
      END IF

      IF LEN(tempLine$) > 0 THEN
        tokenizeLine tempLine$

        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

        IF lineTokenCount > 0 THEN
          firstTok$ = lineTokens$(0)
          tVal = lineTokenVals(0)
          isUdtLine = 0

          IF tVal = TOK_DECLARE THEN
            isUdtLine = 1 ' Mark as handled so it ignores SUB/FUNCTION registration
            IF lineTokenCount >= 3 THEN
              tVal2 = lineTokenVals(1)
              IF tVal2 = TOK_SUB OR tVal2 = TOK_FUNCTION THEN
                dName$ = UCASE$(lineTokens$(2))
                dRetType = TYPE_UNDEFINED ' Default inert type for SUB

                IF tVal2 = TOK_FUNCTION THEN
                  declares(declareCount).IsFunction = 1

                  IF dName$ = "" THEN
                    throwCompilerError "EXPECTED FUNCTION NAME", ASIS, 0
                    EXIT SUB
                  END IF

                  suffix$ = RIGHT$(dName$, 1)
                  dRetType = TYPE_SINGLE
                  IF suffix$ = "$" THEN dRetType = TYPE_STRING
                  IF suffix$ = "#" THEN dRetType = TYPE_DOUBLE
                  IF suffix$ = "!" THEN dRetType = TYPE_SINGLE
                  IF suffix$ = "%" THEN dRetType = TYPE_INTEGER
                  IF suffix$ = "&" THEN dRetType = TYPE_LONG
                  IF suffix$ <> "$" AND suffix$ <> "#" AND suffix$ <> "!" AND suffix$ <> "%" AND suffix$ <> "&" THEN
                    charIdx = ASC(LEFT$(dName$, 1)) - 65
                    IF charIdx >= 0 AND charIdx <= 25 THEN
                      IF defIntMap(charIdx) = 1 THEN dRetType = TYPE_INTEGER
                    END IF
                  END IF
                ELSE
                  declares(declareCount).IsFunction = 0
                END IF

                declares(declareCount).RecordName = dName$
                declares(declareCount).RetType = dRetType
                declares(declareCount).LineNumber = currentLineNumber
                declares(declareCount).ArgCount = 0

                tokIdx = 3
                IF tokIdx < lineTokenCount THEN
                  IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
                    tokIdx = tokIdx + 1
                    DO WHILE tokIdx < lineTokenCount
                      argTok$ = lineTokens$(tokIdx)
                      IF lineTokenVals(tokIdx) = 256 + ASC(")") THEN EXIT DO
                      IF lineTokenVals(tokIdx) = 0 THEN
                        aName$ = UCASE$(argTok$)

                        IF aName$ = "" THEN
                          throwCompilerError "EXPECTED ARGUMENT NAME", ASIS, 0
                          EXIT SUB
                        END IF

                        aType = TYPE_SINGLE
                        suffix$ = RIGHT$(aName$, 1)
                        IF suffix$ = "$" THEN aType = TYPE_STRING
                        IF suffix$ = "#" THEN aType = TYPE_DOUBLE
                        IF suffix$ = "!" THEN aType = TYPE_SINGLE
                        IF suffix$ = "%" THEN aType = TYPE_INTEGER
                        IF suffix$ = "&" THEN aType = TYPE_LONG
                        IF suffix$ <> "$" AND suffix$ <> "#" AND suffix$ <> "!" AND suffix$ <> "%" AND suffix$ <> "&" THEN
                          charIdx = ASC(LEFT$(aName$, 1)) - 65
                          IF charIdx >= 0 AND charIdx <= 25 THEN
                            IF defIntMap(charIdx) = 1 THEN aType = TYPE_INTEGER
                          END IF
                        END IF

                        aArray = 0

                        IF tokIdx + 1 < lineTokenCount THEN
                          IF lineTokenVals(tokIdx + 1) = 256 + ASC("(") THEN
                            IF tokIdx + 2 < lineTokenCount THEN
                              IF lineTokenVals(tokIdx + 2) = 256 + ASC(")") THEN
                                aArray = 2
                                tokIdx = tokIdx + 2
                              ELSE
                                throwCompilerError "EXPECTED )", ASIS, 0
                                EXIT SUB
                              END IF
                            ELSE
                              throwCompilerError "EXPECTED )", ASIS, 0
                              EXIT SUB
                            END IF
                          END IF
                        END IF

                        IF tokIdx + 1 < lineTokenCount THEN
                          IF lineTokenVals(tokIdx + 1) = TOK_AS THEN
                            tokIdx = tokIdx + 2
                            tokIdx = parseTypeClause(tokIdx, lineTokenCount - 1) - 1
                            aType = returnedData2
                            IF aType = TYPE_UNDEFINED THEN EXIT SUB
                          END IF
                        END IF

                        IF declares(declareCount).ArgCount < 16 THEN
                          declareArgType(declareCount, declares(declareCount).ArgCount) = aType
                          declareArgArray(declareCount, declares(declareCount).ArgCount) = aArray
                          declares(declareCount).ArgCount = declares(declareCount).ArgCount + 1
                        ELSE
                          throwCompilerError "TOO MANY ARGS IN DECLARE", ASIS, 0
                          EXIT SUB
                        END IF
                      END IF

                      tokIdx = tokIdx + 1
                      IF tokIdx < lineTokenCount THEN
                        IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
                          tokIdx = tokIdx + 1
                        ELSE
                          IF lineTokenVals(tokIdx) = 256 + ASC(")") THEN
                          ELSE
                            throwCompilerError "EXPECTED COMMA IN DECLARE", ASIS, 0
                            EXIT SUB
                          END IF
                        END IF
                      END IF
                    LOOP
                  END IF
                END IF

                declareCount = declareCount + 1
                compileText$(iy) = "" ' Erase line so Pass 5 ignores it

              ELSE
                throwCompilerError "EXPECTED SUB OR FUNCTION AFTER DECLARE", ASIS, 0
                EXIT SUB
              END IF
            ELSE
              throwCompilerError "MALFORMED DECLARE", ASIS, 0
              EXIT SUB
            END IF
          END IF

          IF tVal = TOK_DATA THEN
            isUdtLine = 1 ' Mark as handled so it ignores SUB/FUNCTION registration
            tokIdx = 1
            DO WHILE tokIdx < lineTokenCount
              itemStr$ = ""
              DO WHILE tokIdx < lineTokenCount
                IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN EXIT DO
                tTok$ = lineTokens$(tokIdx)
                IF LEFT$(tTok$, 1) = CHR$(34) THEN
                  itemStr$ = itemStr$ + extractQuotes$(tTok$)
                ELSE
                  itemStr$ = itemStr$ + retTokenText$(tTok$)
                END IF
                tokIdx = tokIdx + 1
              LOOP

              IF dataItemCount >= 10000 THEN
                throwCompilerError "DATA LIMIT REACHED", ASIS, 0
                EXIT SUB
              END IF

              ff = resolveSymbol("!G_SYS_DATA_ITEM_" + cTrNum$(dataItemCount) + "_DESC$")
              IF ff = 1 THEN
                descIdx = returnedData2
                strVarData$(descIdx) = itemStr$
                dataItemDescIdx(dataItemCount) = descIdx
              END IF
              dataItemCount = dataItemCount + 1

              IF tokIdx < lineTokenCount THEN
                IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN tokIdx = tokIdx + 1
              END IF
            LOOP
            compileText$(iy) = "" ' Erase line so Pass 5 ignores it
          END IF

          IF inTypeBlock = 1 THEN
            isUdtLine = 1
            IF tVal = TOK_END THEN
              IF lineTokenCount >= 2 THEN
                IF lineTokenVals(1) = TOK_TYPE THEN
                  inTypeBlock = 0
                  compileText$(iy) = "" ' Erase line so Pass 5 ignores it
                ELSE
                  throwCompilerError "EXPECTED TYPE AFTER END", ASIS, 0
                  EXIT SUB
                END IF
              ELSE
                throwCompilerError "EXPECTED TYPE AFTER END", ASIS, 0
                EXIT SUB
              END IF
            ELSE
              fName$ = UCASE$(firstTok$)

              IF lineTokenCount >= 3 THEN
                IF lineTokenVals(1) = TOK_AS THEN
                  tokIdx = 2
                  fieldSize = 0
                  fieldType = 0
                  tempUdtIndex = 0
                  tempIsDynamicString = 0

                  tokIdx = parseTypeClause(tokIdx, lineTokenCount - 1)
                  fieldType = returnedData2
                  typeData = returnedData3

                  IF fieldType = TYPE_UNDEFINED THEN EXIT SUB

                  IF fieldType = TYPE_UDT THEN tempUdtIndex = typeData
                  IF fieldType = TYPE_STRING THEN fixedLen = typeData

                  SELECT CASE fieldType
                    CASE TYPE_BYTE, TYPE_UBYTE: fieldSize = 1
                    CASE TYPE_INTEGER, TYPE_UINTEGER: fieldSize = 2
                    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: fieldSize = 4
                    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: fieldSize = 8
                    CASE TYPE_STRING
                      IF fixedLen > 0 THEN
                        fieldSize = fixedLen
                      ELSE
                        fieldSize = 8
                        tempIsDynamicString = 1
                      END IF
                    CASE TYPE_UDT
                      fieldSize = udts(tempUdtIndex).TotalSize
                  END SELECT

                  IF udts(currentUdtIdx).FieldCount >= 64 THEN
                    throwCompilerError "UDT FIELD LIMIT REACHED", ASIS, 0
                    EXIT SUB
                  END IF

                  fIdx = udts(currentUdtIdx).FieldCount
                  udtFields(currentUdtIdx, fIdx).FieldName = fName$
                  udtFields(currentUdtIdx, fIdx).DataType = fieldType
                  udtFields(currentUdtIdx, fIdx).Offset = udts(currentUdtIdx).TotalSize
                  udtFields(currentUdtIdx, fIdx).Size = fieldSize
                  udtFields(currentUdtIdx, fIdx).UDTIndex = tempUdtIndex
                  udtFields(currentUdtIdx, fIdx).IsDynamicString = tempIsDynamicString

                  udts(currentUdtIdx).TotalSize = udts(currentUdtIdx).TotalSize + fieldSize
                  udts(currentUdtIdx).FieldCount = udts(currentUdtIdx).FieldCount + 1

                  compileText$(iy) = "" ' Erase line so Pass 5 ignores it
                ELSE
                  throwCompilerError "EXPECTED AS", ASIS, 0
                  EXIT SUB
                END IF
              ELSE
                throwCompilerError "MALFORMED UDT FIELD", ASIS, 0
                EXIT SUB
              END IF
            END IF
          ELSE
            IF tVal = TOK_TYPE THEN
              isUdtLine = 1
              IF currentScopeID <> 0 THEN
                throwCompilerError "TYPE MUST BE GLOBAL", ASIS, 0
                EXIT SUB
              END IF
              IF lineTokenCount >= 2 THEN
                uName$ = UCASE$(lineTokens$(1))
                FOR ii = 0 TO udtCount - 1
                  IF RTRIM$(udts(ii).RecordName) = uName$ THEN
                    throwCompilerError "DUPLICATE UDT NAME", ASIS, 0
                    EXIT SUB
                  END IF
                NEXT

                IF udtCount >= 64 THEN
                  throwCompilerError "UDT LIMIT REACHED", ASIS, 0
                  EXIT SUB
                END IF

                udts(udtCount).RecordName = uName$
                udts(udtCount).FieldCount = 0
                udts(udtCount).TotalSize = 0
                currentUdtIdx = udtCount
                udtCount = udtCount + 1
                inTypeBlock = 1

                compileText$(iy) = "" ' Erase line so Pass 5 ignores it
              ELSE
                throwCompilerError "EXPECTED UDT NAME", ASIS, 0
                EXIT SUB
              END IF
            END IF
          END IF

          IF isUdtLine = 0 THEN
            IF tVal = TOK_SUB OR tVal = TOK_FUNCTION OR tVal = TOK_DEF THEN
              IF lineTokenCount >= 2 THEN
                nameIdx = 1
                subName$ = UCASE$(lineTokens$(1))

                IF tVal = TOK_DEF THEN
                  IF subName$ = "FN" THEN
                    IF lineTokenCount >= 3 THEN
                      nameIdx = 2
                      subName$ = "FN" + UCASE$(lineTokens$(2))
                    END IF
                  END IF
                END IF

                IF tVal = TOK_DEF AND subName$ = "SEG" THEN
                ELSE
                  ff = resolveSymbol(subName$)
                  IF ff = 0 THEN EXIT SUB
                  vIdx = returnedData2

                  IF symbols(vIdx).SubIndex <> 0 THEN
                    throwCompilerError "DUPLICATE SUB OR FUNCTION", ASIS, 0
                    EXIT SUB
                  END IF

                  symbols(vIdx).SubIndex = subCount
                  subs(subCount).RecordName = subName$
                  subs(subCount).ArgCount = 0
                  scopeCounter = scopeCounter + 1
                  currentScopeID = scopeCounter
                  subs(subCount).ScopeID = currentScopeID

                  IF tVal = TOK_FUNCTION OR tVal = TOK_DEF THEN
                    subs(subCount).IsFunction = 1
                  ELSE
                    subs(subCount).IsFunction = 0
                    symbols(vIdx).DataType = TYPE_UNDEFINED
                  END IF

                  ff = resolveSymbol(subName$)
                  IF ff = 1 THEN subs(subCount).ReturnVarIdx = returnedData2

                  tokIdx = nameIdx + 1
                  IF tokIdx < lineTokenCount THEN
                    IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
                      tokIdx = tokIdx + 1
                      DO WHILE tokIdx < lineTokenCount
                        argTok$ = lineTokens$(tokIdx)
                        IF lineTokenVals(tokIdx) = 256 + ASC(")") THEN EXIT DO
                        IF lineTokenVals(tokIdx) = 0 THEN
                          argName$ = UCASE$(argTok$)

                          ff = resolveSymbol(argName$)
                          IF ff = 0 THEN EXIT SUB
                          vIdxArg = returnedData2

                          ' Flag as explicit so lookahead typing ignores it (bypass implicit lookahead resolution)
                          symbols(vIdxArg).IsExplicit = 1

                          ' Force arguments global to allow caller-callee communication
                          symbols(vIdxArg).IsLocal = 0

                          IF tokIdx + 1 < lineTokenCount THEN
                            IF lineTokenVals(tokIdx + 1) = 256 + ASC("(") THEN
                              IF tokIdx + 2 < lineTokenCount THEN
                                IF lineTokenVals(tokIdx + 2) = 256 + ASC(")") THEN
                                  symbols(vIdxArg).IsArray = 2
                                  tokIdx = tokIdx + 2
                                ELSE
                                  throwCompilerError "EXPECTED )", ASIS, 0
                                  EXIT SUB
                                END IF
                              ELSE
                                throwCompilerError "EXPECTED )", ASIS, 0
                                EXIT SUB
                              END IF
                            END IF
                          END IF

                          IF tokIdx + 1 < lineTokenCount THEN
                            IF lineTokenVals(tokIdx + 1) = TOK_AS THEN
                              tokIdx = tokIdx + 2
                              tokIdx = parseTypeClause(tokIdx, lineTokenCount - 1) - 1
                              dtMapped = returnedData2
                              typeData = returnedData3

                              IF dtMapped = TYPE_UNDEFINED THEN EXIT SUB

                              symbols(vIdxArg).DataType = dtMapped
                              IF dtMapped = TYPE_UDT THEN
                                symbols(vIdxArg).UDTIndex = typeData
                              END IF
                            END IF
                          END IF

                          IF subs(subCount).ArgCount < 16 THEN
                            subArgVarIdx(subCount, subs(subCount).ArgCount) = vIdxArg
                            subs(subCount).ArgCount = subs(subCount).ArgCount + 1
                          ELSE
                            throwCompilerError "TOO MANY ARGS", ASIS, 0
                            EXIT SUB
                          END IF
                        END IF
                        tokIdx = tokIdx + 1
                        IF tokIdx < lineTokenCount THEN
                          IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
                            tokIdx = tokIdx + 1
                          ELSE
                            IF lineTokenVals(tokIdx) = 256 + ASC(")") THEN
                            ELSE
                              throwCompilerError "EXPECTED COMMA", ASIS, 0
                              EXIT SUB
                            END IF
                          END IF
                        END IF
                      LOOP
                    END IF
                  END IF
                  subCount = subCount + 1

                  IF tVal = TOK_DEF THEN
                    currentScopeID = 0
                  END IF
                END IF
              END IF
            END IF

            IF tVal = TOK_END THEN
              IF lineTokenCount >= 2 THEN
                IF lineTokenVals(1) = TOK_SUB OR lineTokenVals(1) = TOK_FUNCTION THEN
                  currentScopeID = 0
                END IF
              END IF
            END IF
          END IF

        END IF
      END IF
    END IF
  NEXT

  IF inTypeBlock = 1 THEN
    throwCompilerError "UNCLOSED TYPE BLOCK", ASIS, 0
    EXIT SUB
  END IF

  FOR iDecl = 0 TO declareCount - 1
    dName$ = RTRIM$(declares(iDecl).RecordName)

    ff = findSubIndex(dName$)
    IF ff = 1 THEN
      subIdx = returnedData2

      IF declares(iDecl).IsFunction <> subs(subIdx).IsFunction THEN
        currentLineNumber = declares(iDecl).LineNumber
        throwCompilerError "DECLARE " + dName$ + " SUB/FUNCTION TYPE MISMATCH", ASIS, 0
        EXIT SUB
      END IF

      IF declares(iDecl).ArgCount <> subs(subIdx).ArgCount THEN
        currentLineNumber = declares(iDecl).LineNumber
        throwCompilerError "DECLARE " + dName$ + " ARG COUNT MISMATCH", ASIS, 0
        EXIT SUB
      END IF

      IF subs(subIdx).IsFunction = 1 THEN
        retVarIdx = subs(subIdx).ReturnVarIdx
        IF declares(iDecl).RetType <> symbols(retVarIdx).DataType THEN
          currentLineNumber = declares(iDecl).LineNumber
          throwCompilerError "DECLARE " + dName$ + " RETURN TYPE MISMATCH", ASIS, 0
          EXIT SUB
        END IF
      END IF

      FOR iArg = 0 TO declares(iDecl).ArgCount - 1
        argVarIdx = subArgVarIdx(subIdx, iArg)

        IF declareArgArray(iDecl, iArg) <> symbols(argVarIdx).IsArray THEN
          currentLineNumber = declares(iDecl).LineNumber
          throwCompilerError "DECLARE " + dName$ + " ARRAY MISMATCH ON ARG " + LTRIM$(STR$(iArg + 1)), ASIS, 0
          EXIT SUB
        END IF

        IF declareArgType(iDecl, iArg) <> TYPE_ANY THEN
          IF declareArgType(iDecl, iArg) <> symbols(argVarIdx).DataType THEN
            currentLineNumber = declares(iDecl).LineNumber
            throwCompilerError "DECLARE " + dName$ + " TYPE MISMATCH ON ARG " + LTRIM$(STR$(iArg + 1)), ASIS, 0
            EXIT SUB
          END IF
        END IF
      NEXT
    END IF
  NEXT

  currentLineNumber = 1
  currentScopeID = 0

END SUB ' compilePass4Symbols

''''''''''''''''''''''''
SUB compilePass5ScanOrEmit

  ' Pass 5: Processes stream-based tokens and emits x64 machine code or builds intermediate IR
  ' Operates in blocks of 4 lines per cycle to yield back to the main UI loop
  ' Dummy mode tracks label offsets while the final mode writes the executable binary

  DIM tempSuccess AS LONG
  DIM stripLen AS LONG
  DIM vIdx AS LONG
  DIM stmtRes AS LONG
  DIM vIdxEnd AS LONG
  DIM vIdxInstant AS LONG

  IF pass5.Line = 1 THEN defaultArrayDynamic = 0

  FOR loopCycle = 1 TO 4
    IF pass5.Line <= compileLastLine THEN
      iy = pass5.Line
      currentLineNumber = editorLineLinkMap(iy)

      curLine$ = compileText$(iy)
      tempLine$ = LTRIM$(RTRIM$(curLine$))

      IF LEN(tempLine$) > 0 THEN

        labelStr$ = retLabelStripLength$(tempLine$)
        stripLen = returnedData2

        IF stripLen > 0 THEN
          labelName$ = "%" + UCASE$(labelStr$)

          ' Find label and set offset
          expectedSymType = TYPE_LABEL
          ff = resolveSymbol(labelName$)
          IF ff = 1 THEN
            vIdx = returnedData2
            symbols(vIdx).Offset = stream.emitPos
            symbols(vIdx).IsExplicit = 1
          END IF

          ' Strip label for keyword scanning on the same line
          tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
        END IF

        IF LEN(tempLine$) > 0 THEN
          tokenizeLine tempLine$

          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            pass5.Success = 0
            EXIT SUB
          END IF

          IF lineTokenCount > 0 THEN

            isStackSpanning = 0
            FOR ii = 0 TO lineTokenCount - 1
              tVal = lineTokenVals(ii)
              IF tVal = TOK_SUB OR tVal = TOK_FUNCTION OR tVal = TOK_DEF THEN
                isStackSpanning = 1
                EXIT FOR
              END IF
            NEXT

            t.TempCounter = 0 ' Ensure ephemeral TIRA tracking is reset for every statement

            preStmtStackOffset = stack.currentStackOffset ' Snapshot the stack offset before compiling the statement

            stmtRes = parseStatement(0)
            IF stmtRes = 0 THEN
              pass5.Success = 0
              EXIT SUB
            END IF

            ' Catch hidden stack alignment bugs right at the source
            IF isStackSpanning = 0 THEN
              IF stack.currentStackOffset <> preStmtStackOffset THEN
                err$ = "FATAL: Stack alignment check failed at line " + retLineNumberStr$ + ". Offset: " + LTRIM$(STR$(stack.currentStackOffset)) + " bytes. Expected " + LTRIM$(STR$(preStmtStackOffset))
                ESCAPETEXT err$
              END IF
            END IF
          END IF
        END IF
      END IF

      pass5.Line = pass5.Line + 1
    ELSE
      ' Finalize Phase
      tempSuccess = pass5.Success

      IF tempSuccess = 1 THEN
        IF ctrlCount > 0 THEN
          addStatusMsg "ERROR: UNCLOSED BLOCK"
          tempSuccess = 0
        END IF
      END IF

      ' Validate that all GOTO targets exist
      IF tempSuccess = 1 THEN
        expectedSymType = TYPE_LABEL
        ff = resolveSymbol("@END_PROGRAM")
        IF ff = 1 THEN
          vIdxEnd = returnedData2
          symbols(vIdxEnd).DataType = TYPE_LABEL
          symbols(vIdxEnd).alreadyParsed = 1
        END IF

        expectedSymType = TYPE_LABEL
        ff = resolveSymbol("@INSTANT_EXIT")
        IF ff = 1 THEN
          vIdxInstant = returnedData2
          symbols(vIdxInstant).DataType = TYPE_LABEL
          symbols(vIdxInstant).alreadyParsed = 1
        END IF

        FOR ii = 0 TO gotoPatchCount - 1
          vIdx = gotoPatches(ii).VarIdx
          IF symbols(vIdx).DataType <> TYPE_LABEL OR symbols(vIdx).alreadyParsed = 0 THEN
            uName$ = RTRIM$(symbols(vIdx).RecordName)
            IF LEFT$(uName$, 1) = "%" OR LEFT$(uName$, 1) = "@" THEN uName$ = MID$(uName$, 2)
            addStatusMsg "ERROR: LABEL " + uName$ + " NOT FOUND"
            tempSuccess = 0
            EXIT FOR
          END IF
        NEXT
      END IF

      pass5.Success = tempSuccess
      pass5.SubState = 2 ' Mark as fully finalized
      EXIT FOR
    END IF
  NEXT

END SUB ' compilePass5ScanOrEmit

''''''''''''''''''''''''
SUB compilePass5bLocalVariables

  ' Pass 5B: Calculates memory footprints and byte offsets for local sub/function variables
  ' Runs just before x64 emission to ensure stack frames are aligned to the Windows ABI
  ' Global variables are handled later to account for temporary TIRA variable generation

  DIM sIdx AS LONG
  DIM localByteSize AS LONG
  DIM remainder AS LONG

  ' Local variable tracking
  ' Calculate LocalOffset for local variables and LocalFrameSize for each subroutine
  FOR iSub = 1 TO subCount - 1
    subs(iSub).LocalFrameSize = 0
  NEXT

  FOR ii = 0 TO symbolCount - 1
    IF symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0 THEN
      ' Find which sub this belongs to via ScopeID
      ff = findSubIndexByScope(symbols(ii).ScopeID)

      IF ff = 1 THEN
        sIdx = returnedData2
        ' Calculate the exact byte size this variable will demand on the stack
        localByteSize = retSymbolByteSize(ii)

        ' Assign offset and increment the subroutine's local frame size requirement
        symbols(ii).LocalOffset = subs(sIdx).LocalFrameSize
        subs(sIdx).LocalFrameSize = subs(sIdx).LocalFrameSize + localByteSize
      END IF
    END IF
  NEXT

  ' Enforce the 16-byte ABI stack alignment rule to lock in the final LocalFrameSize
  FOR iSub = 1 TO subCount - 1
    remainder = subs(iSub).LocalFrameSize MOD 16
    IF remainder <> 0 THEN
      subs(iSub).LocalFrameSize = subs(iSub).LocalFrameSize + (16 - remainder)
    END IF
  NEXT

END SUB ' compilePass5bLocalVariables

''''''''''''''''''''''''
SUB compilePass6GlobalMap

  ' Pass 6: Calculates final executable payload offsets for strings, variables, and descriptors
  ' This executes strictly after Pass 5 emission to guarantee that all ephemeral
  ' TIRA intermediate variables and expression temporaries are mapped into the data segment

  ' No variables need declaring, only loops and ff used

  '''' Global variable layout tracking
  textLayout.TotalStrSize = 0
  textLayout.TotalVarSize = 0
  textLayout.TotalDescSize = 0

  FOR ii = 0 TO symbolCount - 1
    ' We skip mapping local variables into the global data segment
    ' since they reside natively on the RBP stack frame
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
      ' Do nothing
    ELSE
      IF symbols(ii).IsArray = 2 THEN
        symbols(ii).Offset = textLayout.TotalVarSize
        textLayout.TotalVarSize = textLayout.TotalVarSize + 8
      ELSE
        IF symbols(ii).DataType = TYPE_STRING THEN
          symbols(ii).Offset = textLayout.TotalVarSize
          IF symbols(ii).IsArray = 1 THEN
            textLayout.TotalVarSize = textLayout.TotalVarSize + retSymbolByteSize(ii)
          ELSE
            textLayout.TotalVarSize = textLayout.TotalVarSize + 8 ' Global string slot
            symbols(ii).DescOffset = textLayout.TotalDescSize
            textLayout.TotalDescSize = textLayout.TotalDescSize + 24

            symbols(ii).StrOffset = textLayout.TotalStrSize
            IF strVarData$(ii) <> "" THEN
              textLayout.TotalStrSize = textLayout.TotalStrSize + LEN(strVarData$(ii)) + 1
            END IF
          END IF
        ELSE
          symbols(ii).Offset = textLayout.TotalVarSize
          textLayout.TotalVarSize = textLayout.TotalVarSize + retSymbolByteSize(ii)
        END IF
      END IF
    END IF
  NEXT

END SUB ' compilePass6GlobalMap

''''''''''''''''''''''''
SUB confirmExit

  drawBorderBox (SCREENSIZEX \ 2) - 156, (SCREENSIZEY \ 2) - 20, 312, 40, 15, 0
  PrintStr (SCREENSIZEX \ 2) - 148, (SCREENSIZEY \ 2) - 4, "PRESS ESC TO CONFIRM, SPACE TO CANCEL", 14, 0, 0
  _DISPLAY

  DO
    limitSpeed
    mouseReadInput

    kVal = keyCheck("ESC")
    IF kVal = 27 THEN
      ESCAPETEXT "PROGRAM ENDED"
    END IF

    kVal2 = keyCheck("SPACE")
    IF kVal2 = 32 THEN
      DO WHILE _KEYDOWN(32)
        limitSpeed
      LOOP
      EXIT DO
    END IF
  LOOP

END SUB ' confirmExit

''''''''''''''''''''''''
SUB createFont

  CLS
  COLOR 15

  FOR iy = 0 TO 15
    FOR ix = 0 TO 15
      wASC = (iy * 16) + ix
      ZLOCATE ix, iy
      IF wASC <> 7 AND wASC <> 12 THEN PRINT CHR$(wASC)
    NEXT
  NEXT

  FOR iy = 0 TO 144
    FOR ix = 0 TO 127
      fontData(ix, iy) = POINT(ix, iy)
    NEXT
  NEXT

  CLS

END SUB ' createFont

''''''''''''''''''''''''
FUNCTION cTrNum$ (wNum)

  cTrNum$ = LTRIM$(RTRIM$(STR$(wNum)))

END FUNCTION ' cTrNum$

''''''''''''''''''''''''
SUB deleteSelection

  IF editor.SelectStartX = editor.CursorX AND editor.SelectStartY = editor.CursorY THEN EXIT SUB

  IF editor.SelectStartY < editor.CursorY OR (editor.SelectStartY = editor.CursorY AND editor.SelectStartX < editor.CursorX) THEN
    startY = editor.SelectStartY
    startX = editor.SelectStartX
    endY = editor.CursorY
    endX = editor.CursorX
  ELSE
    startY = editor.CursorY
    startX = editor.CursorX
    endY = editor.SelectStartY
    endX = editor.SelectStartX
  END IF

  leftPart$ = LEFT$(editorText$(startY), startX)
  rightPart$ = MID$(editorText$(endY), endX + 1)

  editorText$(startY) = leftPart$ + rightPart$

  linesToRemove = endY - startY
  IF linesToRemove > 0 THEN
    FOR ii = startY + 1 TO editor.LastLine - linesToRemove
      editorText$(ii) = editorText$(ii + linesToRemove)
    NEXT
    FOR ii = editor.LastLine - linesToRemove + 1 TO editor.LastLine
      editorText$(ii) = ""
    NEXT
    editor.LastLine = editor.LastLine - linesToRemove
    IF editor.LastLine < 1 THEN editor.LastLine = 1
  END IF

  editor.CursorX = startX
  editor.CursorY = startY
  editor.SelectStartX = startX
  editor.SelectStartY = startY

  IF editor.CursorY < editor.ScrollY THEN editor.ScrollY = editor.CursorY
  IF editor.CursorY >= editor.ScrollY + 28 THEN editor.ScrollY = editor.CursorY - 27
  IF editor.CursorX < editor.ScrollX THEN editor.ScrollX = editor.CursorX
  IF editor.CursorX >= editor.ScrollX + 56 THEN editor.ScrollX = editor.CursorX - 55

END SUB ' deleteSelection

''''''''''''''''''''''''
SUB displayFlashText

  IF flashTextTimer > 0 THEN
    COLOR sysColor.flashTextClr
    flashTextTimer = flashTextTimer - 1
    PrintTextLineWithBanners flashText$, sysColor.flashTextClr, BOTTOM
  END IF

END SUB ' displayFlashText

''''''''''''''''''''''''
SUB drawBorderBox (wPosX, wPosY, wSizeX, wSizeY, fgClr, bgClr)

  IF wSizeX <= 1 THEN EXIT SUB
  IF wSizeY <= 1 THEN EXIT SUB

  endX = wPosX + wSizeX - 1
  endY = wPosY + wSizeY - 1

  IF endX > SCREENSIZEX - 1 THEN endX = SCREENSIZEX - 1
  IF endY > SCREENSIZEY - 1 THEN endY = SCREENSIZEY - 1

  LINE (wPosX, wPosY)-(endX, endY), fgClr, B
  LINE (wPosX + 1, wPosY + 1)-(endX - 1, endY - 1), bgClr, BF

END SUB ' drawBorderBox

''''''''''''''''''''''''
SUB drawButtonsPMI

  editorBoxTop = editor.StartY

  funcListBoxH = (13 * 10) + 4

  hasCode = 0
  FOR ii = 1 TO editor.LastLine
    IF editorText$(ii) <> "" THEN
      hasCode = 1
      EXIT FOR
    END IF
  NEXT

  btnSaveTxtW = 122
  btnSaveTxtH = 20
  btnSaveTxtX = RIGHT_BOX_X
  btnSaveTxtY = editorBoxTop + funcListBoxH + 8

  IF hasCode = 0 THEN
    btnSaveTxtBg = sysColor.gray
  ELSE
    btnSaveTxtBg = editor.windowBarClr
  END IF

  drawBorderBox btnSaveTxtX, btnSaveTxtY, btnSaveTxtW, btnSaveTxtH, 15, btnSaveTxtBg
  PrintStr btnSaveTxtX + 29, btnSaveTxtY + 6, "SAVE BAS", 15, 0, 1

  btnLoadTxtW = 122
  btnLoadTxtH = 20
  btnLoadTxtX = btnSaveTxtX
  btnLoadTxtY = btnSaveTxtY + btnSaveTxtH + 8

  drawBorderBox btnLoadTxtX, btnLoadTxtY, btnLoadTxtW, btnLoadTxtH, 15, editor.windowBarClr
  PrintStr btnLoadTxtX + 29, btnLoadTxtY + 6, "LOAD BAS", 15, 0, 1

  btnCompileW = 122
  btnCompileH = 20
  btnCompileX = btnSaveTxtX
  btnCompileY = btnLoadTxtY + btnLoadTxtH + 8

  IF compileState <> COMP_IDLE OR hasCode = 0 THEN
    btnCompileBg = sysColor.gray
  ELSE
    btnCompileBg = editor.windowBarClr
  END IF

  drawBorderBox btnCompileX, btnCompileY, btnCompileW, btnCompileH, 15, btnCompileBg
  PrintStr btnCompileX + 33, btnCompileY + 6, "COMPILE", 15, 0, 1

  btnSearchW = 122
  btnSearchH = 20
  btnSearchX = btnSaveTxtX
  btnSearchY = btnCompileY + btnCompileH + 8

  IF hasCode = 0 THEN
    btnSearchBg = sysColor.gray
  ELSE
    btnSearchBg = editor.windowBarClr
  END IF

  drawBorderBox btnSearchX, btnSearchY, btnSearchW, btnSearchH, 15, btnSearchBg
  PrintStr btnSearchX + 37, btnSearchY + 6, "SEARCH", 15, 0, 1

  IF mouseClickedInBox(btnSaveTxtX, btnSaveTxtY, btnSaveTxtW, btnSaveTxtH) THEN
    IF hasCode = 1 THEN
      editor.Focus = 1
      addStatusMsg "SAVING " + fileNameCode$ + "..."
      fileCodeSave
      addStatusMsg "SAVED " + fileNameCode$
    END IF
  END IF

  IF mouseClickedInBox(btnLoadTxtX, btnLoadTxtY, btnLoadTxtW, btnLoadTxtH) THEN
    editor.Focus = 1
    IF _FILEEXISTS(fileNameCode$) THEN
      addStatusMsg "LOADING " + fileNameCode$ + "..."
      fileCodeLoad
      refineCode (0)
      editor.CursorX = 0
      editor.CursorY = 1
      editor.ScrollY = 1
      editor.ScrollX = 0
      editor.SelectStartX = 0
      editor.SelectStartY = 1
      editor.IsSelecting = 0
      addStatusMsg "LOADED " + fileNameCode$
    ELSE
      addStatusMsg "ERROR: " + fileNameCode$ + " DOES NOT EXIST"
    END IF
  END IF

  IF mouseClickedInBox(btnCompileX, btnCompileY, btnCompileW, btnCompileH) THEN
    IF compileState = COMP_IDLE AND hasCode = 1 THEN
      editor.Focus = 1
      statusMsgCount = 1
      editor.StatusScrollY = 1
      editor.StatusSelectedIndex = 0
      FOR ii = 1 TO 999
        statusMsg$(ii) = ""
      NEXT
      compileState = COMP_REFINE
      addStatusMsg "REFINING..."
    END IF
  END IF

  IF mouseClickedInBox(btnSearchX, btnSearchY, btnSearchW, btnSearchH) THEN
    IF hasCode = 1 THEN
      editor.Focus = 1
      searchModal
    END IF
  END IF

END SUB ' drawButtonsPMI

''''''''''''''''''''''''
SUB drawClearBox (wPosX, wPosY, wSizeX, wSizeY, fgClr)

  IF wSizeX <= 1 THEN EXIT SUB
  IF wSizeY <= 1 THEN EXIT SUB

  endX = wPosX + wSizeX - 1
  endY = wPosY + wSizeY - 1

  IF endX > SCREENSIZEX - 1 THEN endX = SCREENSIZEX - 1
  IF endY > SCREENSIZEY - 1 THEN endY = SCREENSIZEY - 1

  LINE (wPosX, wPosY)-(endX, endY), fgClr, B

END SUB ' drawClearBox

''''''''''''''''''''''''
SUB drawCornerPMI

  closeBtnW = 15
  closeBtnX = SCREENSIZEX - closeBtnW
  closeBtnY = 0
  closeBtnH = 13

  dropW = 35
  dropH = 15
  dropX = SCREENSIZEX - dropW
  dropY = 12

  minW = 16
  minH = 15
  minX = dropX - minW + 1
  minY = 12

  blankX = minX
  blankW = closeBtnX - minX + 1
  blankY = 0
  blankH = 13

  IF editor.TopMenuFocus = 4 THEN
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, sysColor.gray
    PrintStr closeBtnX + 4, closeBtnY + 3, "?", 15, 0, 1
  ELSE
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, 0, 1
  END IF

  IF editor.TopMenuFocus = 4 OR isFullscreen = 0 THEN
    drawBorderBox blankX, blankY, blankW, blankH, 15, editor.windowBarClr
    IF mouseWithinBoxBounds(blankX, blankY, blankW, blankH) THEN
      drawClearBox blankX + 1, blankY + 1, blankW - 2, blankH - 2, 9
    END IF
    PrintStr blankX + 6, blankY + 3, "RES", 15, 0, 1
  END IF

  IF editor.TopMenuFocus = 4 THEN
    drawBorderBox dropX, dropY, dropW, dropH, 15, editor.windowBarClr
    ' Use dropY + 1 and dropH - 1 for hit detection to keep Y=12 for the top row
    IF mouseWithinBoxBounds(dropX, dropY + 1, dropW, dropH - 1) THEN
      drawClearBox dropX + 1, dropY + 1, dropW - 2, dropH - 2, editor.CloseClr
    END IF
    PrintStr dropX + 6, dropY + 4, "END", 15, 0, 1

    drawBorderBox minX, minY, minW, minH, 15, editor.windowBarClr
    ' Use minY + 1 and minH - 1 for hit detection to keep Y=12 for the top row
    IF mouseWithinBoxBounds(minX, minY + 1, minW, minH - 1) THEN
      drawClearBox minX + 1, minY + 1, minW - 2, minH - 2, 9
    END IF
    PrintChr minX + 4, minY + 4, CHR$(25), 15, 0, 1

    ' Shadow effect on the left and bottom edges of the expanded popup
    LINE (minX - 1, 0)-(minX - 1, dropY + dropH), 0
    LINE (minX - 1, dropY + dropH)-(dropX + dropW - 1, dropY + dropH), 0

    IF keyCheck("SPACE") THEN
      editor.MenuClicked = 1
      IF isFullscreen = 0 THEN
        isFullscreen = 1
        _FULLSCREEN _SQUAREPIXELS
      ELSE
        isFullscreen = 0
        _FULLSCREEN _OFF
      END IF
      editor.TopMenuFocus = 0
      waitKeyRelease "SPACE"
    END IF

    IF keyCheck("*") THEN
      editor.MenuClicked = 1
      drawClearBox dropX + 1, dropY + 1, dropW - 2, dropH - 2, editor.CloseClr
      _DISPLAY
      waitTimer 0.1
      ESCAPETEXT "PROGRAM ENDED"
    END IF
  END IF

  IF mouseClickedInBox(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
    IF editor.TopMenuFocus = 4 THEN
      editor.TopMenuFocus = 0
    ELSE
      editor.TopMenuFocus = 4
      editor.Focus = 0
    END IF
    editor.MenuClicked = 1
  END IF

  IF editor.TopMenuFocus = 4 OR isFullscreen = 0 THEN
    IF mouseClickedInBox(blankX, blankY, blankW, blankH) THEN
      editor.MenuClicked = 1
      IF isFullscreen = 0 THEN
        isFullscreen = 1
        _FULLSCREEN _SQUAREPIXELS
      ELSE
        isFullscreen = 0
        _FULLSCREEN _OFF
      END IF
      editor.TopMenuFocus = 0
    END IF
  END IF

  IF editor.TopMenuFocus = 4 THEN
    IF mouseClickedInBox(dropX, dropY + 1, dropW, dropH - 1) THEN
      editor.MenuClicked = 1
      mouse.Released1 = 0
      ESCAPETEXT "PROGRAM ENDED"
    END IF

    IF mouseClickedInBox(minX, minY + 1, minW, minH - 1) THEN
      editor.MenuClicked = 1
      _SCREENICON
      editor.TopMenuFocus = 0
    END IF

    IF mouseClickedInBox(SCREENSIZEX - 35, 0, 35, 27) THEN editor.MenuClicked = 1
  END IF

END SUB ' drawCornerPMI

''''''''''''''''''''''''
SUB drawEditorPMI

  editorBoxTop = editor.StartY
  editorBoxY = editorBoxTop + 3

  editorTextX = EDITOR_BOX_X + LEFT_SPACING
  editorTextW = 56 * 8

  textRows = 28
  textH = textRows * 10
  editorBoxH = textH + 3

  editorScrollBarX = editorTextX + editorTextW + 3
  editorScrollBarY = editorBoxTop
  editorScrollBarW = 10

  hScrollY = editorBoxY + textH
  hScrollX = 1
  hScrollW = (editorScrollBarX + editorScrollBarW) - hScrollX

  IF editor.Focus = 1 THEN
    focusX = 0
    focusY = editorBoxTop - 1
    focusW = (editorScrollBarX + editorScrollBarW + 1) - focusX
    focusH = (editorBoxH + 8) + 2
    drawClearBox focusX, focusY, focusW, focusH, sysColor.focusBorder
  END IF

  newBoxX = 1
  newBoxW = (editorScrollBarX + editorScrollBarW) - newBoxX
  drawBorderBox newBoxX, editorBoxTop, newBoxW, editorBoxH + 8, 15, 0

  LINE (EDITOR_BOX_X, editorBoxTop)-(EDITOR_BOX_X, editorBoxTop + editorBoxH + 7), 15

  IF editor.Focus = 1 THEN
    LINE (EDITOR_BOX_X - 1, editorBoxTop + 1)-(EDITOR_BOX_X - 1, hScrollY - 1), sysColor.focusBorder
  END IF

  ' Draw Horizontal Scrollbar
  drawBorderBox hScrollX, hScrollY, hScrollW, 8, 15, 0
  PrintChr hScrollX + 2, hScrollY, CHR$(17), 15, 0, 1
  PrintChr hScrollX + hScrollW - 9, hScrollY, CHR$(16), 15, 0, 1

  ' Calculate maxLen for horizontal scrolling
  maxLen = 0
  FOR iy = 1 TO editor.LastLine
    i2 = LEN(editorText$(iy))
    IF i2 > maxLen THEN maxLen = i2
  NEXT
  maxScrollX = maxLen - 56 + 2
  IF maxScrollX < 0 THEN maxScrollX = 0
  IF editor.ScrollX > maxScrollX THEN editor.ScrollX = maxScrollX

  ' Draw H-Scroll thumb
  thumbWEd = hScrollW - 20
  IF maxScrollX = 0 THEN
    thumbSizeX = thumbWEd
    thumbXEd = hScrollX + 10
  ELSE
    thumbSizeX = (56 * thumbWEd) \ (maxLen + 2)
    IF thumbSizeX < 8 THEN thumbSizeX = 8
    thumbXEd = hScrollX + 10 + ((editor.ScrollX * (thumbWEd - thumbSizeX)) \ maxScrollX)
  END IF
  LINE (thumbXEd, hScrollY + 1)-(thumbXEd + thumbSizeX - 1, hScrollY + 6), 15, BF

  FOR iy = 0 TO textRows - 1
    actualY = iy + editor.ScrollY
    lineNum = actualY
    numStr$ = LTRIM$(RTRIM$(STR$(lineNum)))
    'numStr$ = "44444"
    numPosX = (EDITOR_BOX_X - 4) - (LEN(numStr$) * 8) ' Leaves exactly 4 pixels to of gap between the left white line and the text

    IF actualY = editor.CursorY THEN
      lineColor = 15
    ELSE
      lineColor = 11
    END IF

    PrintStr numPosX, editorBoxY + (iy * 10) + 1, numStr$, lineColor, 0, 1


    IF editor.IsSelecting = 1 THEN
      IF editor.SelectStartY < editor.CursorY OR (editor.SelectStartY = editor.CursorY AND editor.SelectStartX < editor.CursorX) THEN
        startY = editor.SelectStartY
        startX = editor.SelectStartX
        endY = editor.CursorY
        endX = editor.CursorX
      ELSE
        startY = editor.CursorY
        startX = editor.CursorX
        endY = editor.SelectStartY
        endX = editor.SelectStartX
      END IF

      IF actualY >= startY AND actualY <= endY THEN
        lineLen = LEN(editorText$(actualY))
        hlStartX = 0
        hlEndX = lineLen

        IF actualY = startY THEN hlStartX = startX
        IF actualY = endY THEN hlEndX = endX
        IF actualY < endY THEN hlEndX = lineLen + 1

        hlStartX = hlStartX - editor.ScrollX
        hlEndX = hlEndX - editor.ScrollX

        IF hlStartX < 0 THEN hlStartX = 0
        IF hlEndX > 56 THEN hlEndX = 56

        IF hlStartX < hlEndX THEN
          LINE (editorTextX + (hlStartX * 8), editorBoxY + (iy * 10))-(editorTextX + (hlEndX * 8) - 1, editorBoxY + (iy * 10) + 9), 1, BF
        END IF
      END IF
    END IF

    IF actualY <= EDITOR_LINE_MAX THEN
      IF editorText$(actualY) <> "" THEN
        printText$ = MID$(editorText$(actualY), editor.ScrollX + 1, 56)
        PrintStr editorTextX, editorBoxY + (iy * 10) + 1, printText$, 15, 0, 1
      END IF
    END IF
  NEXT

  IF editor.Focus = 1 THEN
    IF editor.CursorY >= editor.ScrollY AND editor.CursorY < editor.ScrollY + textRows THEN
      IF editor.CursorX >= editor.ScrollX AND editor.CursorX < editor.ScrollX + 56 THEN
        cursorPixelX = editorTextX + ((editor.CursorX - editor.ScrollX) * 8)
        cursorPixelY = editorBoxY + ((editor.CursorY - editor.ScrollY) * 10) + 1

        cursorBlink = INT(TIMER * 2) AND 1
        IF cursorBlink = 1 THEN
          PrintChr cursorPixelX, cursorPixelY, "*", 14, 0, 1
        ELSE
          PrintChr cursorPixelX, cursorPixelY, "_", 14, 0, 1
        END IF
      END IF
    END IF
  END IF

  ' Mouse Processing Logic
  lastLine = editor.LastLine
  IF editor.CursorY > lastLine THEN lastLine = editor.CursorY

  IF mouse.Wheel <> 0 THEN
    IF mouseWithinBoxBounds(editorTextX, editorBoxTop, editorTextW + editorScrollBarW + 4, editorBoxH + 8) THEN
      editor.Focus = 1
      editor.ScrollY = editor.ScrollY + mouse.Wheel
      maxScroll = lastLine - 27
      IF maxScroll < 1 THEN maxScroll = 1
      IF editor.ScrollY > maxScroll THEN editor.ScrollY = maxScroll
      IF editor.ScrollY < 1 THEN editor.ScrollY = 1
    END IF
  END IF

  IF mouse.Clicked1 THEN
    lastActionWasTyping = 0
    editor.DragActive = 0
    editor.ScrollDragActiveX = 0

    IF mouseWithinBoxBounds(editorTextX, editorBoxY, editorTextW, textH) THEN
      editor.DragActive = 1
      editor.Focus = 1
      clickRelX = mouse.PosX - editorTextX
      clickRelY = mouse.PosY - editorBoxY
      newCX = (clickRelX \ 8) + editor.ScrollX
      newCY = (clickRelY \ 10) + editor.ScrollY

      IF newCY <> editor.CursorY THEN
        refineCode (0)
      END IF

      IF newCY > lastLine THEN newCY = lastLine

      lineLength = LEN(editorText$(newCY))
      IF newCX > lineLength THEN newCX = lineLength

      IF _KEYDOWN(100303) OR _KEYDOWN(100304) THEN
        IF editor.IsSelecting = 0 THEN
          editor.SelectStartX = editor.CursorX
          editor.SelectStartY = editor.CursorY
          editor.IsSelecting = 1
        END IF
        editor.CursorX = newCX
        editor.CursorY = newCY
      ELSE
        IF editor.TextClickActive = 1 AND (TIMER - editor.TextLastClickTime) < 0.3 THEN
          editor.TextClickActive = 0 ' Reset to prevent triple-click looping
          editor.DragActive = 0 ' Disable drag logic to prevent immediate overwrite of the right-bound selection

          lineStr$ = editorText$(newCY)
          lineLen = LEN(lineStr$)

          IF lineLen > 0 THEN
            clickPos = newCX + 1
            IF clickPos > lineLen THEN clickPos = lineLen

            ch$ = MID$(lineStr$, clickPos, 1)
            cType = 3
            IF ch$ = " " OR ch$ = CHR$(9) THEN
              cType = 1
            ELSE
              IF INSTR("(),=+-*/\" + CHR$(34) + ":<>';[]{}", ch$) > 0 THEN
                cType = 2
              END IF
            END IF

            leftBound = clickPos - 1
            DO WHILE leftBound > 0
              ch$ = MID$(lineStr$, leftBound, 1)
              lType = 3
              IF ch$ = " " OR ch$ = CHR$(9) THEN
                lType = 1
              ELSE
                IF INSTR("(),=+-*/\" + CHR$(34) + ":<>';[]{}", ch$) > 0 THEN
                  lType = 2
                END IF
              END IF
              IF lType <> cType THEN EXIT DO
              leftBound = leftBound - 1
            LOOP

            rightBound = clickPos + 1
            DO WHILE rightBound <= lineLen
              ch$ = MID$(lineStr$, rightBound, 1)
              rType = 3
              IF ch$ = " " OR ch$ = CHR$(9) THEN
                rType = 1
              ELSE
                IF INSTR("(),=+-*/\" + CHR$(34) + ":<>';[]{}", ch$) > 0 THEN
                  rType = 2
                END IF
              END IF
              IF rType <> cType THEN EXIT DO
              rightBound = rightBound + 1
            LOOP

            editor.SelectStartX = leftBound
            editor.SelectStartY = newCY
            editor.CursorX = rightBound - 1
            editor.CursorY = newCY
            editor.IsSelecting = 1
          ELSE
            editor.SelectStartX = newCX
            editor.SelectStartY = newCY
            editor.IsSelecting = 0
            editor.CursorX = newCX
            editor.CursorY = newCY
          END IF
        ELSE
          editor.TextLastClickTime = TIMER
          editor.TextClickActive = 1
          editor.SelectStartX = newCX
          editor.SelectStartY = newCY
          editor.IsSelecting = 0
          editor.CursorX = newCX
          editor.CursorY = newCY
        END IF
      END IF
    END IF

    IF mouseWithinBoxBounds(0, editorBoxY, editorTextX, textH) THEN
      editor.DragActive = 1
      editor.Focus = 1
      clickRelY = mouse.PosY - editorBoxY
      newCY = (clickRelY \ 10) + editor.ScrollY

      IF newCY <> editor.CursorY THEN
        refineCode (0)
      END IF

      IF newCY > lastLine THEN newCY = lastLine
      IF newCY < 1 THEN newCY = 1

      editor.CursorX = 0
      editor.CursorY = newCY
      editor.SelectStartX = 0
      editor.SelectStartY = newCY
      editor.IsSelecting = 0
    END IF

    IF mouseWithinBoxBounds(hScrollX, hScrollY, hScrollW, 8) THEN
      editor.Focus = 1
      IF mouseWithinBoxBounds(thumbXEd, hScrollY, thumbSizeX, 8) THEN
        editor.ScrollDragActiveX = 1
        editor.ScrollDragOffsetX = mouse.PosX - thumbXEd
      ELSE
        IF mouseWithinBoxBounds(hScrollX, hScrollY, 10, 8) THEN
          editor.ScrollX = editor.ScrollX - 1
          IF editor.ScrollX < 0 THEN editor.ScrollX = 0
        ELSE
          IF mouseWithinBoxBounds(hScrollX + hScrollW - 10, hScrollY, 10, 8) THEN
            editor.ScrollX = editor.ScrollX + 1
            IF editor.ScrollX > maxScrollX THEN editor.ScrollX = maxScrollX
          ELSE
            IF mouse.PosX < thumbXEd THEN
              editor.ScrollX = editor.ScrollX - 10
              IF editor.ScrollX < 0 THEN editor.ScrollX = 0
            ELSE
              editor.ScrollX = editor.ScrollX + 10
              IF editor.ScrollX > maxScrollX THEN editor.ScrollX = maxScrollX
            END IF
          END IF
        END IF
      END IF
    END IF
  END IF

  IF mouse.Button1Down AND mouse.Clicked1 = 0 THEN
    IF editor.Focus = 1 AND editor.DragActive = 1 THEN
      clickRelX = mouse.PosX - editorTextX
      clickRelY = mouse.PosY - editorBoxY
      newCX = (clickRelX \ 8) + editor.ScrollX
      newCY = (clickRelY \ 10) + editor.ScrollY

      maxScroll = lastLine - 27
      IF maxScroll < 1 THEN maxScroll = 1

      IF mouse.PosY < editorBoxY THEN
        newCY = editor.ScrollY - 1
        IF newCY < 1 THEN newCY = 1
        editor.ScrollY = newCY
      END IF
      IF mouse.PosY >= editorBoxY + textH THEN
        newCY = editor.ScrollY + textRows
        editor.ScrollY = editor.ScrollY + 1
        IF editor.ScrollY > maxScroll THEN editor.ScrollY = maxScroll
      END IF

      IF mouse.PosX < editorTextX THEN
        newCX = editor.ScrollX - 1
        IF newCX < 0 THEN newCX = 0
        editor.ScrollX = newCX
      END IF
      IF mouse.PosX >= editorTextX + editorTextW THEN
        newCX = editor.ScrollX + 56
        editor.ScrollX = editor.ScrollX + 1
        IF editor.ScrollX > maxScrollX THEN editor.ScrollX = maxScrollX
      END IF

      IF newCY < 1 THEN newCY = 1
      IF newCY > lastLine THEN newCY = lastLine

      lineLength = LEN(editorText$(newCY))
      IF newCX > lineLength THEN newCX = lineLength
      IF newCX < 0 THEN newCX = 0

      IF newCX <> editor.CursorX OR newCY <> editor.CursorY THEN
        editor.IsSelecting = 1
        editor.CursorX = newCX
        editor.CursorY = newCY
      END IF
    END IF
  END IF

  IF mouse.Button1Down AND editor.ScrollDragActiveX = 1 THEN
    IF maxScrollX > 0 THEN
      newThumbX = mouse.PosX - editor.ScrollDragOffsetX
      trackSizeX = thumbWEd - thumbSizeX
      IF trackSizeX > 0 THEN
        newScrollX = ((newThumbX - (hScrollX + 10)) * maxScrollX) \ trackSizeX
        IF newScrollX < 0 THEN newScrollX = 0
        IF newScrollX > maxScrollX THEN newScrollX = maxScrollX
        editor.ScrollX = newScrollX
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    editor.DragActive = 0
    editor.ScrollDragActiveX = 0
  END IF

  IF mouse.Released2 THEN
    IF mouseWithinBoxBounds(editorTextX, editorBoxY, editorTextW, textH) AND mouseDown2WithinBoxBounds(editorTextX, editorBoxY, editorTextW, textH) THEN
      editor.MenuMode = 1
    END IF
  END IF

END SUB ' drawEditorPMI

''''''''''''''''''''''''
SUB drawFuncListPMI

  editorBoxTop = editor.StartY

  funcListBoxX = RIGHT_BOX_X
  funcListBoxY = editorBoxTop
  funcListBoxW = 122
  funcListBoxH = (13 * 10) + 4

  scrollBarX = funcListBoxX + funcListBoxW - 10
  scrollBarY = funcListBoxY
  scrollBarW = 10
  scrollBarH = funcListBoxH

  drawBorderBox funcListBoxX, funcListBoxY, funcListBoxW, funcListBoxH, 15, 0

  maxLines = 12

  IF editor.MenuMode = 0 THEN
    funcScrollY = processVScrollbar(scrollBarX, scrollBarY, scrollBarW, scrollBarH, uiSubCount, maxLines, funcScrollY, editor.FuncScrollDragActive, editor.FuncScrollDragOffsetY, 0)
    editor.FuncScrollDragActive = returnedData2
    editor.FuncScrollDragOffsetY = returnedData3

    PrintStr funcListBoxX + 25, funcListBoxY + 4, "GO TO TOP", 15, 0, 1
    FOR ii = 0 TO 11
      subIdx = ii + funcScrollY
      IF subIdx < uiSubCount THEN
        sOutName$ = LEFT$(uiSubName$(subIdx), 13)

        isCurrent = 0
        startLine = uiSubLine(subIdx)
        endLine = editor.LastLine
        IF subIdx + 1 < uiSubCount THEN
          endLine = uiSubLine(subIdx + 1) - 1
        END IF

        IF editor.CursorY >= startLine AND editor.CursorY <= endLine THEN
          isCurrent = 1
        END IF

        IF isCurrent = 1 THEN
          listColor = 15
        ELSE
          listColor = 11
        END IF

        PrintStr funcListBoxX + RIGHT_BOX_SPACING, funcListBoxY + ((ii + 1) * 10) + 4, sOutName$, listColor, 0, 1
      END IF
    NEXT
  ELSE
    PrintStr funcListBoxX + 15, funcListBoxY + 4, "CUT", 15, 0, 1
    PrintStr funcListBoxX + 15, funcListBoxY + 14, "COPY", 15, 0, 1
    PrintStr funcListBoxX + 15, funcListBoxY + 24, "PASTE", 15, 0, 1
    PrintStr funcListBoxX + 15, funcListBoxY + 34, "CANCEL", 15, 0, 1
  END IF

  ' Mouse Processing Logic
  IF mouse.Wheel <> 0 THEN
    IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY, funcListBoxW, funcListBoxH) THEN
      funcScrollY = funcScrollY + mouse.Wheel
      maxFuncScroll = uiSubCount - maxLines
      IF maxFuncScroll < 0 THEN maxFuncScroll = 0
      IF funcScrollY > maxFuncScroll THEN funcScrollY = maxFuncScroll
      IF funcScrollY < 0 THEN funcScrollY = 0
    END IF
  END IF

  IF mouse.Clicked1 THEN
    IF editor.MenuMode = 1 THEN
      IF mouseClickedInBox(funcListBoxX, funcListBoxY + 3, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 3
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "CUT", 15, 0, 1
        _DISPLAY
        waitTimer UI_FLASH_TIME

        undo_StateSave
        lastActionWasTyping = 0

        copyText$ = retEditorSelection$
        IF copyText$ <> "" THEN _CLIPBOARD$ = copyText$
        deleteSelection
        editor.IsSelecting = 0
        editor.MenuMode = 0
      END IF
      IF mouseClickedInBox(funcListBoxX, funcListBoxY + 13, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 13
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "COPY", 15, 0, 1
        _DISPLAY
        waitTimer UI_FLASH_TIME

        copyText$ = retEditorSelection$
        IF copyText$ <> "" THEN _CLIPBOARD$ = copyText$
        editor.MenuMode = 0
      END IF
      IF mouseClickedInBox(funcListBoxX, funcListBoxY + 23, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 23
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "PASTE", 15, 0, 1
        _DISPLAY
        waitTimer UI_FLASH_TIME

        undo_StateSave
        lastActionWasTyping = 0

        pasteClipboardText
        editor.MenuMode = 0
      END IF
      IF mouseClickedInBox(funcListBoxX, funcListBoxY + 33, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 33
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "CANCEL", 15, 0, 1
        _DISPLAY
        waitTimer UI_FLASH_TIME

        editor.MenuMode = 0
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    IF editor.MenuMode = 1 THEN
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY, funcListBoxW, funcListBoxH) = 0 THEN
        editor.MenuMode = 0
      END IF
    END IF

    IF editor.MenuMode = 0 THEN
      IF mouseClickedInBox(funcListBoxX, funcListBoxY, funcListBoxW - 10, funcListBoxH) THEN
        clickRelY = mouse.PosY - (funcListBoxY + 3)
        IF clickRelY < 0 THEN clickRelY = 0
        clickedRow = clickRelY \ 10
        IF clickedRow = 0 THEN
          rowY = funcListBoxY + 3
          LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 11, rowY + 9), 1, BF
          PrintStr funcListBoxX + 25, rowY + 1, "GO TO TOP", 15, 0, 1
          _DISPLAY
          waitTimer UI_FLASH_TIME

          editor.CursorY = 1
          editor.CursorX = 0
          editor.ScrollY = 1
          editor.ScrollX = 0
          editor.SelectStartX = 0
          editor.SelectStartY = 1
          editor.IsSelecting = 0
        ELSE
          subIdx = (clickedRow - 1) + funcScrollY
          IF subIdx < uiSubCount THEN
            rowY = funcListBoxY + 3 + (clickedRow * 10)
            LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 11, rowY + 9), 1, BF
            PrintStr funcListBoxX + RIGHT_BOX_SPACING, rowY + 1, LEFT$(uiSubName$(subIdx), 13), 15, 0, 1
            _DISPLAY
            waitTimer UI_FLASH_TIME

            editor.CursorY = uiSubLine(subIdx)
            editor.CursorX = 0
            editor.ScrollY = editor.CursorY - 14
            IF editor.ScrollY < 1 THEN editor.ScrollY = 1
            editor.ScrollX = 0
            editor.SelectStartX = 0
            editor.SelectStartY = 1
            editor.IsSelecting = 0
          END IF
        END IF
      END IF
    END IF
  END IF

END SUB ' drawFuncListPMI

''''''''''''''''''''''''
SUB drawStatusPMI

  editorBoxTop = editor.StartY
  editorBoxY = editorBoxTop + 3

  editorTextX = EDITOR_BOX_X + LEFT_SPACING
  editorTextW = 56 * 8
  editorBoxH = 283

  statusBoxX = 1
  statusBoxY = editorBoxY + editorBoxH + 8
  statusBoxW = editorTextX + editorTextW + 3
  statusBoxH = 38

  scrollBarX = statusBoxX + statusBoxW - 1
  scrollBarY = statusBoxY
  scrollBarW = 10
  scrollBarH = statusBoxH

  IF editor.Focus = 2 THEN
    sFocusX = statusBoxX - 1
    sFocusY = statusBoxY - 1
    sFocusW = (scrollBarX + scrollBarW + 1) - sFocusX
    sFocusH = statusBoxH + 2
    drawClearBox sFocusX, sFocusY, sFocusW, sFocusH, sysColor.focusBorder
  END IF

  drawBorderBox statusBoxX, statusBoxY, statusBoxW, statusBoxH, 15, 0

  maxLines = (statusBoxH - 8) \ 10
  editor.StatusScrollY = processVScrollbar(scrollBarX, scrollBarY, scrollBarW, scrollBarH, (statusMsgCount - 1), maxLines, editor.StatusScrollY, editor.StatusScrollDragActive, editor.StatusScrollDragOffsetY, 1)
  editor.StatusScrollDragActive = returnedData2
  editor.StatusScrollDragOffsetY = returnedData3

  lineY = statusBoxY + 5
  linesDrawn = 0
  FOR ii = editor.StatusScrollY TO statusMsgCount - 1
    IF linesDrawn >= maxLines THEN EXIT FOR

    ' Highlight selected line if the status bar is focused
    IF ii = editor.StatusSelectedIndex AND editor.Focus = 2 THEN
      LINE (statusBoxX + 1, lineY - 1)-(scrollBarX - 1, lineY + 8), 1, BF
      PrintStr statusBoxX + LEFT_SPACING, lineY, statusMsg$(ii), 15, 0, 1
    ELSE
      PrintStr statusBoxX + LEFT_SPACING, lineY, statusMsg$(ii), 14, 0, 1
    END IF

    lineY = lineY + 10
    linesDrawn = linesDrawn + 1
  NEXT

  ' Mouse Processing Logic
  IF mouse.Wheel <> 0 THEN
    IF mouseWithinBoxBounds(statusBoxX, statusBoxY, statusBoxW + scrollBarW, statusBoxH) THEN
      editor.Focus = 2
      editor.StatusScrollY = editor.StatusScrollY + mouse.Wheel
      IF (statusMsgCount - 1) > maxLines THEN
        IF editor.StatusScrollY > statusMsgCount - maxLines THEN editor.StatusScrollY = statusMsgCount - maxLines
      ELSE
        editor.StatusScrollY = 1
      END IF
      IF editor.StatusScrollY < 1 THEN editor.StatusScrollY = 1
    END IF
  END IF

  IF mouse.Clicked1 THEN
    IF mouseWithinBoxBounds(statusBoxX, statusBoxY, statusBoxW + scrollBarW, statusBoxH) THEN
      editor.Focus = 2
    END IF
  END IF

  IF mouse.Released1 THEN
    IF mouseClickedInBox(statusBoxX, statusBoxY, statusBoxW, statusBoxH) THEN
      clickRelY = mouse.PosY - (statusBoxY + 5)
      clickedRow = clickRelY \ 10
      IF clickedRow >= 0 AND clickedRow < maxLines THEN
        msgIdx = editor.StatusScrollY + clickedRow
        IF msgIdx < statusMsgCount THEN
          editor.StatusSelectedIndex = msgIdx
          clickedMsg$ = statusMsg$(msgIdx)

          IF LEFT$(clickedMsg$, 11) = "ERROR line " OR LEFT$(clickedMsg$, 13) = "WARNING line " THEN
            IF LEFT$(clickedMsg$, 11) = "ERROR line " THEN
              colonPos = INSTR(clickedMsg$, ":")
              startPos = 12
            ELSE
              colonPos = INSTR(clickedMsg$, ":")
              startPos = 14
            END IF

            IF colonPos > startPos - 1 THEN
              lineStr$ = MID$(clickedMsg$, startPos, colonPos - startPos)
              errLine = VAL(lineStr$)
              IF errLine > 0 THEN
                editor.CursorY = errLine
                editor.CursorX = 0
                editor.ScrollY = errLine - 14
                IF editor.ScrollY < 1 THEN editor.ScrollY = 1
                editor.ScrollX = 0
                editor.SelectStartX = 0
                editor.SelectStartY = errLine
                editor.IsSelecting = 0
                editor.Focus = 1
              END IF
            END IF
          END IF
        ELSE
          editor.StatusSelectedIndex = 0
        END IF
      ELSE
        editor.StatusSelectedIndex = 0
      END IF
    END IF
  END IF

END SUB ' drawStatusPMI

''''''''''''''''''''''''
SUB drawTopMenuAndScrollPMI

  editorBoxTop = editor.StartY
  editorBoxY = editorBoxTop + 3

  editorTextX = EDITOR_BOX_X + LEFT_SPACING
  editorTextW = 56 * 8

  textRows = 28
  textH = textRows * 10
  editorBoxH = textH + 3

  editorScrollBarX = editorTextX + editorTextW + 3
  editorScrollBarY = editorBoxTop
  editorScrollBarW = 10
  editorScrollBarH = textH + 4

  hScrollY = editorBoxY + textH

  ' Draw Top Menu Background
  LINE (0, 0)-(SCREENSIZEX - 1, 12), editor.windowBarClr, BF

  DIM fileMenu$(1)
  fileMenu$(0) = "OPEN"
  fileMenu$(1) = "SAVE AS"

  IF editor.TopMenuFocus = 1 THEN
    drawClearBox 4, 1, 34, 11, 9
    PrintStr 6, 3, "FILE", 15, 0, 1

    ff = processDropdownMenu(4, 11, 2, fileMenu$())
    IF ff = 1 THEN
      clickedIdx = returnedData2
    END IF

    fnBoxX = 75
    fnBoxY = 11
    fnBoxW = 17 + (LEN(fileNameCode$) * 8)
    fnBoxH = 16

    LINE (fnBoxX, fnBoxY + 1)-(fnBoxX + fnBoxW - 2, fnBoxY + fnBoxH - 2), editor.windowBarClr, BF
    LINE (fnBoxX, fnBoxY)-(fnBoxX + fnBoxW - 1, fnBoxY), 15
    LINE (fnBoxX + fnBoxW - 1, fnBoxY)-(fnBoxX + fnBoxW - 1, fnBoxY + fnBoxH - 1), 15
    LINE (fnBoxX, fnBoxY + fnBoxH - 1)-(fnBoxX + fnBoxW - 1, fnBoxY + fnBoxH - 1), 15

    PrintStr 84, 15, fileNameCode$, 11, 0, 1

    IF ff = 1 THEN
      IF clickedIdx = 0 THEN
        editor.TopMenuFocus = 0
        fileMenuOpenModal
      END IF
      IF clickedIdx = 1 THEN
        editor.TopMenuFocus = 0
        fileMenuSaveModal
      END IF
    END IF
  ELSE
    PrintStr 6, 3, "FILE", 15, 0, 1
  END IF

  DIM editMenu$(0)
  IF undoState.Ready = 1 THEN
    editMenu$(0) = "UNDO"
  ELSE
    editMenu$(0) = "~UNDO"
  END IF

  IF editor.TopMenuFocus = 2 THEN
    drawClearBox 44, 1, 34, 11, 9
    PrintStr 46, 3, "EDIT", 15, 0, 1

    ff = processDropdownMenu(44, 11, 1, editMenu$())
    IF ff = 1 THEN
      clickedIdx = returnedData2
      IF clickedIdx = 0 THEN
        editor.TopMenuFocus = 0
        undo_StateRestore
      END IF
    END IF
  ELSE
    PrintStr 46, 3, "EDIT", 15, 0, 1
  END IF

  DIM viewMenu$(0)
  viewMenu$(0) = "VIEW SUBS"

  IF editor.TopMenuFocus = 3 THEN
    drawClearBox 84, 1, 34, 11, 9
    PrintStr 86, 3, "VIEW", 15, 0, 1

    ff = processDropdownMenu(84, 11, 1, viewMenu$())
    IF ff = 1 THEN
      clickedIdx = returnedData2
      IF clickedIdx = 0 THEN
        editor.TopMenuFocus = 0
        viewSubsModal
      END IF
    END IF
  ELSE
    PrintStr 86, 3, "VIEW", 15, 0, 1
  END IF

  lastLine = editor.LastLine
  IF editor.CursorY > lastLine THEN lastLine = editor.CursorY

  editor.ScrollY = processVScrollbar(editorScrollBarX, editorScrollBarY, editorScrollBarW, editorScrollBarH, lastLine, textRows, editor.ScrollY, editor.ScrollDragActive, editor.ScrollDragOffsetY, 1)
  editor.ScrollDragActive = returnedData2
  editor.ScrollDragOffsetY = returnedData3

  ' Draw Corner Box
  drawBorderBox editorScrollBarX, hScrollY, editorScrollBarW, 8, 15, 0

  ' Mouse Processing Logic
  IF mouse.Clicked1 THEN
    IF mouseWithinBoxBounds(editorScrollBarX, editorScrollBarY, editorScrollBarW, editorScrollBarH) THEN
      editor.Focus = 1
    END IF

    IF mouseWithinBoxBounds(editorScrollBarX, hScrollY, editorScrollBarW, 8) THEN
      editor.Focus = 1
      IF editor.CornerClickActive = 1 AND (TIMER - editor.CornerLastClickTime) < 0.25 THEN
        ' Double-click detected
        lastLine = editor.LastLine
        IF editor.CursorY > lastLine THEN lastLine = editor.CursorY

        maxScroll = lastLine - 27
        IF maxScroll < 1 THEN maxScroll = 1

        editor.ScrollY = maxScroll
        editor.CursorY = lastLine
        editor.CursorX = 0
        editor.CornerClickActive = 0 ' Reset for next double-click
      ELSE
        ' Single-click, set timer
        editor.CornerLastClickTime = TIMER
        editor.CornerClickActive = 1
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    IF mouseClickedInBox(4, 1, 32, 10) THEN
      IF editor.TopMenuFocus = 1 THEN
        editor.TopMenuFocus = 0
      ELSE
        editor.TopMenuFocus = 1
        editor.Focus = 0
      END IF
      editor.MenuClicked = 1
    END IF

    IF mouseClickedInBox(44, 1, 32, 10) THEN
      IF editor.TopMenuFocus = 2 THEN
        editor.TopMenuFocus = 0
      ELSE
        editor.TopMenuFocus = 2
        editor.Focus = 0
      END IF
      editor.MenuClicked = 1
    END IF

    IF mouseClickedInBox(84, 1, 32, 10) THEN
      IF editor.TopMenuFocus = 3 THEN
        editor.TopMenuFocus = 0
      ELSE
        editor.TopMenuFocus = 3
        editor.Focus = 0
      END IF
      editor.MenuClicked = 1
    END IF
  END IF

END SUB ' drawTopMenuAndScrollPMI

''''''''''''''''''''''''
SUB emitByteCode (wByte AS _UNSIGNED _BYTE)

  IF isDummyPass = 1 THEN
    stream.emitPos = stream.emitPos + 1
    EXIT SUB
  END IF

  intermediateCode(stream.emitPos) = wByte
  stream.emitPos = stream.emitPos + 1

END SUB ' emitByteCode

''''''''''''''''''''''''
SUB emitBytes32 (wVal AS LONG)

  DIM uVal AS _UNSIGNED LONG

  uVal = wVal
  emitByteCode (uVal AND 255)
  emitByteCode ((uVal \ 256) AND 255)
  emitByteCode ((uVal \ 65536) AND 255)
  emitByteCode ((uVal \ 16777216) AND 255)

END SUB ' emitBytes32

''''''''''''''''''''''''
SUB emitEpilogue

  epilogueStartPos = stream.emitPos

  tira_Start

  SELECT CASE compileHasGraphics

    CASE 0 ' Console epilogue

      tiraCall "RT_CRLF", 0, ""
      tiraCall "RT_PRINT_STR", 1, "!G_IO_PAUSE_DESC$"

      ' hStdin = GetStdHandle(-10)
      tiraCall "IAT_GETSTDHANDLE", 1, "-10"
      hStdin$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraNew TC_GET_RET, hStdin$

      ' SetConsoleMode(hStdin, 0) to disable line input and echo
      tiraCall "IAT_SETCONSOLEMODE", 2, hStdin$ + ", 0"

      ' ReadFile (Wait for key)
      bwPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
      bwVal$ = tiraDimVar$("T", TYPE_LONG)
      tiraOp TC_ADDRESS_OF, bwPtr$, bwVal$, ""
      tiraCall "IAT_READFILE", 5, hStdin$ + ", !G_MEM_TEMP_HEAP_PTR, 1, " + bwPtr$ + ", 0"

      ' Restore Console Mode to standard flags (503) to prevent terminal lockup
      tiraCall "IAT_SETCONSOLEMODE", 2, hStdin$ + ", 503"

      tiraLabel "@INSTANT_EXIT"
      tiraCall "IAT_EXITPROCESS", 1, "!G_SYS_EXIT_VAL"

    CASE 1 ' Graphics epilogue

      tiraCall "RT_CRLF", 0, ""
      tiraCall "RT_CRLF", 0, ""
      tiraCall "RT_PRINT_STR", 1, "!G_IO_PAUSE_DESC$"

      ' 1. Wait until NO keys are pressed
      relLoop$ = tiraLabelCreateNew$("REL_WAIT")
      tiraLabel relLoop$
      tiraCall "IAT_SLEEP", 1, "10"

      idx$ = tiraDimVar$("T", TYPE_LONG)
      tiraAssign idx$, "8"

      relKeyLoop$ = tiraLabelCreateNew$("REL_KEY_LOOP")
      tiraLabel relKeyLoop$
      tiraCall "IAT_GETASYNCKEYSTATE", 1, idx$
      state$ = tiraDimVar$("T", TYPE_LONG)
      tiraNew TC_GET_RET, state$

      tiraOp TC_AND, state$, state$, "32768"
      tiraJmpCond "JNE", state$, "0", relLoop$ ' Restart if any key is pressed

      tiraOp TC_ADD, idx$, idx$, "1"
      tiraJmpCond "JLE", idx$, "255", relKeyLoop$

      ' 2. Wait until ANY key is pressed
      pressLoop$ = tiraLabelCreateNew$("PRESS_WAIT")
      tiraLabel pressLoop$
      tiraCall "IAT_SLEEP", 1, "10"

      tiraAssign idx$, "8"

      pressKeyLoop$ = tiraLabelCreateNew$("PRESS_KEY_LOOP")
      tiraLabel pressKeyLoop$
      tiraCall "IAT_GETASYNCKEYSTATE", 1, idx$
      tiraNew TC_GET_RET, state$

      tiraOp TC_AND, state$, state$, "32768"
      doneLbl$ = tiraLabelCreateNew$("DONE")
      tiraJmpCond "JNE", state$, "0", doneLbl$ ' Exit if any key is pressed

      tiraOp TC_ADD, idx$, idx$, "1"
      tiraJmpCond "JLE", idx$, "255", pressKeyLoop$

      tiraJmp pressLoop$ ' Restart press wait loop

      tiraLabel doneLbl$
      tiraLabel "@INSTANT_EXIT"
      tiraCall "IAT_EXITPROCESS", 1, "!G_SYS_EXIT_VAL"

  END SELECT ' compileHasGraphics

  tira_EndAndProcess

  metrics.EpilogueSize = stream.emitPos - epilogueStartPos

END SUB ' emitEpilogue

''''''''''''''''''''''''
SUB emitMemoryOperand (regField AS LONG, baseReg AS LONG, dispType AS LONG, dispVal AS LONG)

  DIM baseRegMod AS LONG
  DIM regFieldMod AS LONG
  DIM modRM AS LONG

  baseRegMod = baseReg AND 7
  regFieldMod = regField AND 7

  IF dispType = 0 THEN
    IF baseRegMod = 5 THEN
      modRM = &H40 + (regFieldMod * 8) + baseRegMod
      emitByteCode modRM
      emitByteCode 0
    ELSE
      modRM = &H00 + (regFieldMod * 8) + baseRegMod
      emitByteCode modRM
      IF baseRegMod = 4 THEN emitByteCode &H24
    END IF
  ELSE
    IF dispType = 8 THEN
      modRM = &H40 + (regFieldMod * 8) + baseRegMod
      emitByteCode modRM
      IF baseRegMod = 4 THEN emitByteCode &H24
      emitByteCode dispVal AND 255
    ELSE
      IF dispType = 32 THEN
        modRM = &H80 + (regFieldMod * 8) + baseRegMod
        emitByteCode modRM
        IF baseRegMod = 4 THEN emitByteCode &H24
        emitBytes32 dispVal
      END IF
    END IF
  END IF

END SUB ' emitMemoryOperand

''''''''''''''''''''''''
SUB emitPrologue

  '''' Prologue
  tira_Start

  ' We allocate the main program frame using TC_MAIN_PROLOGUE instead of TC_ABI_PROLOGUE,
  ' because initStackLayout precisely calculates consoleFrameSize assuming no RBX push,
  ' which TC_ABI_PROLOGUE would alter and misalign hardcoded slot offsets.
  tiraNew TC_MAIN_PROLOGUE, LTRIM$(STR$(currentFrameSize))

  ' Save the base stack pointer layout so the error handler knows where the stack began cleanly
  tiraNew TC_GET_RSP, "!G_SYS_SAFE_RSP_PTR"

  ' Register the Vectored Exception Handler Block
  vehPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, vehPtr$, "RT_VEH_HANDLER", ""
  tiraCall "IAT_ADDVECTOREDEXCEPTIONHANDLER", 2, "1, " + vehPtr$

  ' Call GetProcessHeap
  tiraCall "IAT_GETPROCESSHEAP", 0, ""

  ' Save rax into !G_MEM_PROCESS_HEAP_PTR
  tiraNew TC_GET_RET, "!G_MEM_PROCESS_HEAP_PTR"

  ' call HeapAlloc
  tiraCall "IAT_HEAPALLOC", 3, "!G_MEM_PROCESS_HEAP_PTR, 8, " + LTRIM$(STR$(TEMP_HEAP_SIZE))

  ' Retrieve allocated pointer
  tiraNew TC_GET_RET, "!G_MEM_TEMP_START_PTR"

  ' Add TEMP_HEAP_SIZE to pointer so it points to the END of the allocated block
  ' This allows string operations (like MID$) to safely subtract memory backwards
  tiraOp TC_ADD, "!G_MEM_TEMP_START_PTR", "!G_MEM_TEMP_START_PTR", LTRIM$(STR$(TEMP_HEAP_SIZE))

  ' Initialize the dynamic tracking heap pointer to the start location
  tiraAssign "!G_MEM_TEMP_HEAP_PTR", "!G_MEM_TEMP_START_PTR"

  ' Setup the DATA and READ layout tracker indexes natively in TIRA memory
  tiraAssign "!G_SYS_DATA_COUNT_VAL", LTRIM$(STR$(dataItemCount))
  tiraAssign "!G_SYS_DATA_PTR_VAL", "0"

  tira_EndAndProcess

  metrics.PrologueSize = stream.emitPos

END SUB ' emitPrologue

''''''''''''''''''''''''
SUB emitPrologueWindowSetup

  ' Sets up the Win64 window, registers the class, and starts the message loop for software rendering

  ' Software rendering mode only

  ' Isolate labels during the dummy pass with a suffix so they do not trigger adjustAllPatchOffsets
  ' This prevents the calculated offsets from being corrupted by the prologue shift
  lblProc$ = "@WND_PROC_ENTRY"
  lblUser$ = "@USER_CODE_ENTRY"

  IF isDummyPass = 1 THEN
    lblProc$ = "@WND_PROC_ENTRY_DUMMY"
    lblUser$ = "@USER_CODE_ENTRY_DUMMY"
  END IF

  ff = resolveSymbol("!G_WND_HWND_PTR")

  '''' Initialize !G_GFX_FG_VAL to white and allocate the setup stack frame
  tira_Start
  tiraNew TC_ABI_PROLOGUE, LTRIM$(STR$(stack.GFX_SETUP_FRAME))
  tiraAssign "!G_GFX_FG_VAL", "16777215"

  ' Initialize the spinlock flag and buffers to zero
  tiraAssign "!G_WND_READY_FLAG", "0"
  tiraAssign "!G_WND_RENDER_LOCK_FLAG", "0"

  tiraOp TC_ADDRESS_OF, "!G_GFX_BUF_FRONT_PTR", "!G_LAYOUT_GFX_BUF_FRONT_ARR", ""
  tiraOp TC_ADDRESS_OF, "!G_GFX_BUF_BACK_PTR", "!G_LAYOUT_GFX_BUF_BACK_ARR", ""
  tiraOp TC_ADDRESS_OF, "!G_FRAMEBUF_FRONT_PTR", "!G_LAYOUT_FRAMEBUF_FRONT_ARR", ""
  tiraOp TC_ADDRESS_OF, "!G_FRAMEBUF_BACK_PTR", "!G_LAYOUT_FRAMEBUF_BACK_ARR", ""

  tiraAssign "!G_GFX_BUF_COUNT_FRONT_VAL", "0"
  tiraAssign "!G_GFX_BUF_COUNT_BACK_VAL", "0"

  ' Initialize autodisplay to ON by default
  tiraAssign "!G_GFX_AUTODISPLAY_FLAG", "1"

  '''' Initialize RECT structure with client area size for AdjustWindowRectEx
  ' RECT - Left(4), Top(4), Right(4), Bottom(4)
  rspBase$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RSP, rspBase$

  ' Left = 0
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 0)) + ", 0, 4"

  ' Top = 0
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 4)) + ", 0, 4"

  ' Calculate scaling factor for #GDOUBLE
  winScale = 1
  IF compileGraphicsDouble = 1 THEN winScale = 2

  ' SET DEFAULT STRETCH DIMS EARLY TO PREVENT DIV BY ZERO DURING WINDOW CREATION
  tiraAssign "!G_LAYOUT_WINDOW_W_VAL", LTRIM$(STR$(gfxConfig.SizeX * winScale))
  tiraAssign "!G_LAYOUT_WINDOW_H_VAL", LTRIM$(STR$(gfxConfig.SizeY * winScale))

  ' Right = gfxConfig.SizeX * winScale
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 8)) + ", " + LTRIM$(STR$(gfxConfig.SizeX * winScale)) + ", 4"

  ' Bottom = gfxConfig.SizeY * winScale
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 12)) + ", " + LTRIM$(STR$(gfxConfig.SizeY * winScale)) + ", 4"

  ' Call AdjustWindowRectEx to calculate total window size
  ' BOOL AdjustWindowRectEx(LPRECT lpRect, DWORD dwStyle, BOOL bMenu, DWORD dwExStyle)
  rectPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, rectPtr$, rspBase$, LTRIM$(STR$(stack.SETUP_SLOT_RECT))

  ' dwStyle = WS_OVERLAPPEDWINDOW (0x00CF0000 -> 13565952 in decimal)
  ' bMenu = 0
  ' dwExStyle = 0
  tiraCall "IAT_ADJUSTWINDOWRECTEX", 4, rectPtr$ + ", 13565952, 0, 0"

  ' Calculate Width - Right - Left
  rightVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, rightVal$ + ", " + rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 8))
  leftVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, leftVal$ + ", " + rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 0))
  widthVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, widthVal$, rightVal$, leftVal$
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_NWIDTH)) + ", " + widthVal$ + ", 4"

  ' Calculate Height - Bottom - Top
  bottomVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, bottomVal$ + ", " + rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 12))
  topVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, topVal$ + ", " + rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_RECT + 4))
  heightVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, heightVal$, bottomVal$, topVal$
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_NHEIGHT)) + ", " + heightVal$ + ", 4"

  '''' RegisterClassExA Setup
  tiraCall "IAT_GETMODULEHANDLEA", 1, "0"
  hInstance$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RET, hInstance$
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HINSTANCE)) + ", " + hInstance$ + ", 8"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_WNDCLASSEX_HINSTANCE)) + ", " + hInstance$ + ", 8"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_CREATE_HINSTANCE)) + ", " + hInstance$ + ", 8"

  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_WNDCLASSEX)) + ", 80, 4" ' cbSize
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_STYLE)) + ", 3, 4" ' style
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_CBCLSEXTRA)) + ", 0, 4" ' cbClsExtra
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_CBWNDEXTRA)) + ", 0, 4" ' cbWndExtra
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HICON)) + ", 0, 8" ' hIcon
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_LPSZMENUNAME)) + ", 0, 8" ' lpszMenuName
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HICONSM)) + ", 0, 8" ' hIconSm

  tiraCall "IAT_LOADCURSORA", 2, "0, 32512"
  hCursor$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RET, hCursor$
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HCURSOR)) + ", " + hCursor$ + ", 8"

  tiraCall "IAT_GETSTOCKOBJECT", 1, "4"
  hBr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RET, hBr$
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HBRBACKGROUND)) + ", " + hBr$ + ", 8"

  ' CW_USEDEFAULT = 0x80000000 = -2147483648
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_X)) + ", -2147483648, 4"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_Y)) + ", -2147483648, 4"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HWNDPARENT)) + ", 0, 8"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HMENU)) + ", 0, 8"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_LPPARAM)) + ", 0, 8"

  ' Extract C-String pointer from !G_WND_CLASS_DESC$ String Descriptor and write to stack slot
  classDataPtrSetup$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, classDataPtrSetup$ + ", !G_WND_CLASS_DESC$"
  tiraNew TC_WRITE_MEM_OFFSET, rspBase$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_LPSZCLASSNAME)) + ", " + classDataPtrSetup$ + ", 8"

  wndProcPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, wndProcPtr$, lblProc$, ""

  ' We need RSP to calculate offsets dynamically
  rspVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RSP, rspVar$

  ' Save WndProc pointer to the stack slot
  tiraNew TC_WRITE_MEM_OFFSET, rspVar$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_LPFNWNDPROC)) + ", " + wndProcPtr$ + ", 8"

  ' Calculate the pointer to the WNDCLASSEX structure
  wndClassPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, wndClassPtr$, rspVar$, LTRIM$(STR$(stack.SETUP_SLOT_WNDCLASSEX))

  ' Call RegisterClassExA using strict TIRA ABI compliance
  tiraCall "IAT_REGISTERCLASSEXA", 1, wndClassPtr$

  ' Extract C-String pointers from the QB64PE String Descriptors
  classDataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, classDataPtr$ + ", !G_WND_CLASS_DESC$"

  titleDataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, titleDataPtr$ + ", !G_WND_TITLE_DESC$"

  ' Arguments 1 to 12 for CreateWindowExA
  argsList$ = "0, " + classDataPtr$ + ", " + titleDataPtr$ + ", 13565952, -2147483648, -2147483648, " + widthVal$ + ", " + heightVal$ + ", 0, 0, " + hInstance$ + ", 0"
  tiraCall "IAT_CREATEWINDOWEXA", 12, argsList$

  ' Retrieve HWND from RAX
  hwndVarSetup$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RET, hwndVarSetup$

  ' Save HWND to the stack slot
  tiraNew TC_WRITE_MEM_OFFSET, rspVar$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HWND)) + ", " + hwndVarSetup$ + ", 8"

  '''' Disable Rounded Corners
  ' Store 1 (DWMWCP_DONOTROUND) into a temporary memory slot. We can safely reuse SETUP_SLOT_HICONSM.
  tiraNew TC_WRITE_MEM_OFFSET, rspVar$ + ", " + LTRIM$(STR$(stack.SETUP_SLOT_HICONSM)) + ", 1, 4"
  attrPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, attrPtr$, rspVar$, LTRIM$(STR$(stack.SETUP_SLOT_HICONSM))

  ' Call DwmSetWindowAttribute (HWND, DWMWA_WINDOW_CORNER_PREFERENCE(33), &attr, size(4))
  tiraCall "IAT_DWMSETWINDOWATTRIBUTE", 4, hwndVarSetup$ + ", 33, " + attrPtr$ + ", 4"

  ' ShowWindow (HWND, SW_SHOWNORMAL(1))
  tiraCall "IAT_SHOWWINDOW", 2, hwndVarSetup$ + ", 1"

  '''' Save HWND to global memory
  tiraAssign "!G_LAYOUT_HWND_VAL", hwndVarSetup$

  '''' CreateThread
  threadEntryPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, threadEntryPtr$, lblUser$, ""

  ' CreateThread(lpThreadAttributes=0, dwStackSize=0, lpStartAddress=threadEntryPtr, lpParameter=0, dwCreationFlags=0, lpThreadId=0)
  tiraCall "IAT_CREATETHREAD", 6, "0, 0, " + threadEntryPtr$ + ", 0, 0, 0"

  '''' Message loop
  lblMsgLoopTop$ = tiraLabelCreateNew$("MSG_LOOP_TOP")
  tiraLabel lblMsgLoopTop$

  tiraNew TC_GET_RSP, "!G_WND_MSG_LOOP_RSP_PTR"
  tiraOp TC_ADD, "!G_WND_MSG_LOOP_PTR", "!G_WND_MSG_LOOP_RSP_PTR", LTRIM$(STR$(stack.GRAPHICS_MSG_SLOT))

  ' PeekMessageA(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax, wRemoveMsg)
  tiraCall "IAT_PEEKMESSAGEA", 5, "!G_WND_MSG_LOOP_PTR, 0, 0, 0, 1"

  tiraNew TC_GET_RET, "!G_WND_MSG_LOOP_RET_VAL"

  lblNoMessage$ = tiraLabelCreateNew$("NO_MESSAGE")
  tiraJmpCond "JE", "!G_WND_MSG_LOOP_RET_VAL", "0", lblNoMessage$

  ' cmp dword [rsp+disp32], 18 (WM_QUIT) -> wMsg is at offset 8 of MSG structure
  tiraNew TC_READ_MEM_OFFSET, "!G_WND_MSG_LOOP_MSGID_VAL, !G_WND_MSG_LOOP_PTR, 8"

  lblExit$ = tiraLabelCreateNew$("MSG_EXIT")
  tiraJmpCond "JE", "!G_WND_MSG_LOOP_MSGID_VAL", "18", lblExit$

  tiraCall "IAT_TRANSLATEMESSAGE", 1, "!G_WND_MSG_LOOP_PTR"
  tiraCall "IAT_DISPATCHMESSAGEA", 1, "!G_WND_MSG_LOOP_PTR"

  tiraJmp lblMsgLoopTop$

  tiraLabel lblNoMessage$
  tiraCall "IAT_SLEEP", 1, "1"
  tiraJmp lblMsgLoopTop$

  tiraLabel lblExit$

  ' ExitProcess
  tiraCall "IAT_EXITPROCESS", 1, "!G_SYS_EXIT_VAL"

  '''' WndProc Context
  ' The thread safety architecture mandates that ALL operations in the Window Procedure
  ' read and write strictly to the local RBP-anchored stack frame using tiraStackVar$.
  ' Do not use global data variables here!

  lblOnDestroy$ = tiraLabelCreateNew$("WND_DESTROY")
  lblOnPaint$ = tiraLabelCreateNew$("WND_PAINT")
  lblOnChar$ = tiraLabelCreateNew$("WND_CHAR")
  lblOnKeyDown$ = tiraLabelCreateNew$("WND_KEYDOWN")
  lblOnKeyUp$ = tiraLabelCreateNew$("WND_KEYUP")
  lblOnDefault$ = tiraLabelCreateNew$("WND_DEFAULT")

  tiraLabel lblProc$
  tiraNew TC_ABI_PROLOGUE, LTRIM$(STR$(stack.GFX_WNDPROC_FRAME))

  ' Declare local variables natively on the local execution stack to immunize against cross-thread overwriting
  msgVal$ = tiraStackVar$("MSG", TYPE_LONG, stack.WNDPROC_SLOT_MSG)
  wParamVal$ = tiraStackVar$("WPARAM", TYPE_INTEGER64, stack.WNDPROC_SLOT_WPARAM)
  lParamVal$ = tiraStackVar$("LPARAM", TYPE_INTEGER64, stack.WNDPROC_SLOT_LPARAM)
  retVal$ = tiraStackVar$("RET", TYPE_INTEGER64, stack.WNDPROC_SLOT_RET)
  hwndVar$ = tiraStackVar$("HWND", TYPE_INTEGER64, stack.WNDPROC_SLOT_HWND)

  ' Evaluate Window Message Arguments dynamically directly into their secure local stack slots
  tiraNew TC_ABI_READ_ARG, hwndVar$ + ", 1"
  tiraNew TC_ABI_READ_ARG, msgVal$ + ", 2"
  tiraNew TC_ABI_READ_ARG, wParamVal$ + ", 3"
  tiraNew TC_ABI_READ_ARG, lParamVal$ + ", 4"

  tiraJmpCond "JE", msgVal$, "2", lblOnDestroy$
  tiraJmpCond "JE", msgVal$, "15", lblOnPaint$
  tiraJmpCond "JE", msgVal$, "258", lblOnChar$
  tiraJmpCond "JE", msgVal$, "256", lblOnKeyDown$
  tiraJmpCond "JE", msgVal$, "257", lblOnKeyUp$

  lblOnMouse$ = tiraLabelCreateNew$("WND_MOUSE")
  tiraJmpCond "JL", msgVal$, "512", lblOnDefault$
  tiraJmpCond "JLE", msgVal$, "522", lblOnMouse$

  tiraJmp lblOnDefault$

  tiraLabel lblOnDefault$
  tiraCall "IAT_DEFWINDOWPROCA", 4, hwndVar$ + ", " + msgVal$ + ", " + wParamVal$ + ", " + lParamVal$
  tiraNew TC_GET_RET, retVal$
  tiraNew TC_ABI_WRITE_RET, retVal$
  tiraNew TC_ABI_EPILOGUE, LTRIM$(STR$(stack.GFX_WNDPROC_FRAME))

  ' .onDestroy:
  tiraLabel lblOnDestroy$
  tiraCall "IAT_POSTQUITMESSAGE", 1, "0"
  tiraAssign retVal$, "0"
  tiraNew TC_ABI_WRITE_RET, retVal$
  tiraNew TC_ABI_EPILOGUE, LTRIM$(STR$(stack.GFX_WNDPROC_FRAME))

  ' .onPaint:
  tiraLabel lblOnPaint$

  paintStruct$ = tiraStackVar$("PAINTSTRUCT", TYPE_STRING, stack.WNDPROC_SLOT_PAINTSTRUCT)
  paintStructPtr$ = tiraStackVar$("PS_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_PAINTSTRUCT_PTR)
  tiraOp TC_ADDRESS_OF, paintStructPtr$, paintStruct$, ""

  '''' BeginPaint
  tiraCall "IAT_BEGINPAINT", 2, hwndVar$ + ", " + paintStructPtr$
  hdcVar$ = tiraStackVar$("HDC", TYPE_INTEGER64, stack.WNDPROC_SLOT_HDC)
  tiraNew TC_GET_RET, hdcVar$

  '''' Create Memory DC
  tiraCall "IAT_CREATECOMPATIBLEDC", 1, hdcVar$
  memDcVar$ = tiraStackVar$("MEMDC", TYPE_INTEGER64, stack.WNDPROC_SLOT_MEMDC)
  tiraNew TC_GET_RET, memDcVar$

  '''' Create Compatible Bitmap
  tiraCall "IAT_CREATECOMPATIBLEBITMAP", 3, hdcVar$ + ", " + LTRIM$(STR$(gfxConfig.SizeX)) + ", " + LTRIM$(STR$(gfxConfig.SizeY))
  hBmpVar$ = tiraStackVar$("HBMP", TYPE_INTEGER64, stack.WNDPROC_SLOT_HBITMAP)
  tiraNew TC_GET_RET, hBmpVar$

  '''' Select Bitmap into Memory DC
  tiraCall "IAT_SELECTOBJECT", 2, memDcVar$ + ", " + hBmpVar$
  oldBmpVar$ = tiraStackVar$("OLD_HBMP", TYPE_INTEGER64, stack.WNDPROC_SLOT_OLD_HBITMAP)
  tiraNew TC_GET_RET, oldBmpVar$

  '''' Fill Memory DC with pure blackness before evaluating individual pixels
  tiraCall "IAT_BITBLT", 9, memDcVar$ + ", 0, 0, " + LTRIM$(STR$(gfxConfig.SizeX)) + ", " + LTRIM$(STR$(gfxConfig.SizeY)) + ", 0, 0, 0, 66"

  '''' Font selection
  fontPtrVar$ = tiraStackVar$("FONT_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_FONT_PTR)
  tiraNew TC_READ_MEM, fontPtrVar$ + ", !G_GFX_FONT_DESC$"
  tiraCall "IAT_CREATEFONTA", 14, "8, 8, 0, 0, 400, 0, 0, 0, 255, 0, 0, 0, 49, " + fontPtrVar$

  hFontVar$ = tiraStackVar$("HFONT", TYPE_INTEGER64, stack.WNDPROC_SLOT_HFONT)
  tiraNew TC_GET_RET, hFontVar$

  tiraCall "IAT_SELECTOBJECT", 2, memDcVar$ + ", " + hFontVar$
  oldFontVar$ = tiraStackVar$("OLD_HFONT", TYPE_INTEGER64, stack.WNDPROC_SLOT_OLD_HFONT)
  tiraNew TC_GET_RET, oldFontVar$

  tiraCall "IAT_SETBKCOLOR", 2, memDcVar$ + ", 0"

  '''' Acquire Spinlock cleanly for presentation safety
  lblPaintSpin$ = tiraLabelCreateNew$("PAINT_SPIN")
  lblPaintAcq$ = tiraLabelCreateNew$("PAINT_ACQ")
  tiraLabel lblPaintSpin$
  spinVal$ = tiraStackVar$("SPIN", TYPE_LONG, stack.WNDPROC_SLOT_COUNT) ' Reusing a stack var slot
  tiraAssign spinVal$, "1"
  tiraNew TC_XCHG, "!G_WND_RENDER_LOCK_FLAG, " + spinVal$ + ", 4"
  tiraJmpCond "JE", spinVal$, "0", lblPaintAcq$
  tiraCall "IAT_SLEEP", 1, "0"
  tiraJmp lblPaintSpin$
  tiraLabel lblPaintAcq$

  '''' High-Speed Framebuffer Blitting via GDI StretchDIBits
  bmiVar$ = tiraStackVar$("BMI", TYPE_LONG, stack.WNDPROC_SLOT_BITMAPINFO)
  bmiPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, bmiPtr$, bmiVar$, ""

  ' biSize = 40
  tiraWriteMem bmiPtr$, "40", "4"

  ' biWidth
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 4, " + LTRIM$(STR$(gfxConfig.SizeX)) + ", 4"

  ' biHeight (negative for top-down)
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 8, " + LTRIM$(STR$(-gfxConfig.SizeY)) + ", 4"

  ' biPlanes = 1 (Word)
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 12, 1, 2"

  ' biBitCount = 8 (Word)
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 14, 8, 2"

  ' biCompression = 0 (BI_RGB)
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 16, 0, 4"

  ' biSizeImage = 0
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 20, 0, 4"

  ' biXPelsPerMeter = 0
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 24, 0, 4"

  ' biYPelsPerMeter = 0
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 28, 0, 4"

  ' biClrUsed = 256
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 32, 256, 4"

  ' biClrImportant = 0
  tiraNew TC_WRITE_MEM_OFFSET, bmiPtr$ + ", 36, 0, 4"

  ' Copy Palette
  palPtr$ = tiraStackVar$("PAL_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_PAL_PTR)
  tiraNew TC_READ_MEM, palPtr$ + ", !G_GFX_PALETTE_DESC$"

  bmiPalPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, bmiPalPtr$, bmiPtr$, "40"

  tiraMemcpy bmiPalPtr$, palPtr$, "1024"

  ' Call StretchDIBits
  argListBlt$ = memDcVar$ + ", 0, 0, " + LTRIM$(STR$(gfxConfig.SizeX)) + ", " + LTRIM$(STR$(gfxConfig.SizeY))
  argListBlt$ = argListBlt$ + ", 0, 0, " + LTRIM$(STR$(gfxConfig.SizeX)) + ", " + LTRIM$(STR$(gfxConfig.SizeY))
  argListBlt$ = argListBlt$ + ", !G_FRAMEBUF_FRONT_PTR, " + bmiPtr$ + ", 0, 13369376"

  tiraCall "IAT_STRETCHDIBITS", 13, argListBlt$

  ' Initialize colorVal$ explicitly for the Text Overlay loop to follow
  colorVal$ = tiraStackVar$("COLOR", TYPE_LONG, stack.WNDPROC_SLOT_COLOR)
  tiraAssign colorVal$, "0"

  '''' Text overlay
  lblSkipText$ = tiraLabelCreateNew$("WND_SKIP_TEXT")
  tiraJmpCond "JE", "!G_GFX_BUF_COUNT_FRONT_VAL", "0", lblSkipText$

  baseItr$ = tiraStackVar$("BASE_ITR", TYPE_INTEGER64, stack.WNDPROC_SLOT_BASE_ITR)
  tiraAssign baseItr$, "!G_GFX_BUF_FRONT_PTR"

  cntItr$ = tiraStackVar$("CNT_ITR", TYPE_LONG, stack.WNDPROC_SLOT_CNT_ITR)
  tiraAssign cntItr$, "!G_GFX_BUF_COUNT_FRONT_VAL"

  lblLoopTop$ = tiraLabelCreateNew$("WND_TEXT_LOOP")
  tiraLabel lblLoopTop$

  tiraNew TC_READ_MEM_OFFSET, colorVal$ + ", " + baseItr$ + ", 12"
  tiraCall "IAT_SETTEXTCOLOR", 2, memDcVar$ + ", " + colorVal$

  xVal$ = tiraStackVar$("X_VAL", TYPE_LONG, stack.WNDPROC_SLOT_X_VAL)
  tiraNew TC_READ_MEM_OFFSET, xVal$ + ", " + baseItr$ + ", 16"

  yVal$ = tiraStackVar$("Y_VAL", TYPE_LONG, stack.WNDPROC_SLOT_Y_VAL)
  tiraNew TC_READ_MEM_OFFSET, yVal$ + ", " + baseItr$ + ", 20"

  strPtr$ = tiraStackVar$("STR_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_STR_PTR)
  tiraOp TC_ADD, strPtr$, baseItr$, "24"

  lenVal$ = tiraStackVar$("LEN_VAL", TYPE_LONG, stack.WNDPROC_SLOT_LEN_VAL)
  tiraNew TC_READ_MEM_OFFSET, lenVal$ + ", " + baseItr$ + ", " + LTRIM$(STR$(GFX_ENTRY_LEN_OFFSET))

  tiraCall "IAT_TEXTOUTA", 5, memDcVar$ + ", " + xVal$ + ", " + yVal$ + ", " + strPtr$ + ", " + lenVal$

  tiraOp TC_ADD, baseItr$, baseItr$, LTRIM$(STR$(layout.GfxBufEntrySize))
  tiraOp TC_SUB, cntItr$, cntItr$, "1"
  tiraJmpCond "JG", cntItr$, "0", lblLoopTop$

  tiraLabel lblSkipText$

  '''' Release Spinlock safely before StretchBlt to maximize concurrent performance
  tiraAssign "!G_WND_RENDER_LOCK_FLAG", "0"

  '''' StretchBlt the MEMDC to HDC scaling everything uniformly
  argList$ = hdcVar$ + ", 0, 0, !G_LAYOUT_WINDOW_W_VAL, !G_LAYOUT_WINDOW_H_VAL"
  argList$ = argList$ + ", " + memDcVar$ + ", 0, 0, " + LTRIM$(STR$(gfxConfig.SizeX)) + ", " + LTRIM$(STR$(gfxConfig.SizeY)) + ", 13369376"

  tiraCall "IAT_STRETCHBLT", 11, argList$

  '''' Cleanup DC
  tiraCall "IAT_SELECTOBJECT", 2, memDcVar$ + ", " + oldFontVar$
  tiraCall "IAT_DELETEOBJECT", 1, hFontVar$
  tiraCall "IAT_SELECTOBJECT", 2, memDcVar$ + ", " + oldBmpVar$
  tiraCall "IAT_DELETEOBJECT", 1, hBmpVar$
  tiraCall "IAT_DELETEDC", 1, memDcVar$

  '''' EndPaint
  tiraCall "IAT_ENDPAINT", 2, hwndVar$ + ", " + paintStructPtr$

  tiraAssign "!G_WND_READY_FLAG", "1"
  tiraAssign retVal$, "0"
  tiraNew TC_ABI_WRITE_RET, retVal$
  tiraNew TC_ABI_EPILOGUE, LTRIM$(STR$(stack.GFX_WNDPROC_FRAME))

  ' .onKeyDown:
  tiraLabel lblOnKeyDown$

  kbdIndex$ = tiraStackVar$("KBD_IDX", TYPE_LONG, stack.WNDPROC_SLOT_MAPPED_KEY)
  tiraOp TC_AND, kbdIndex$, wParamVal$, "255"
  kbdStateAddr$ = tiraStackVar$("KBD_STATE_ADDR", TYPE_INTEGER64, stack.WNDPROC_SLOT_KEY_STATE)
  tiraOp TC_ADDRESS_OF, kbdStateAddr$, "!G_LAYOUT_KBD_STATE_ARR", ""
  tiraOp TC_ADD, kbdStateAddr$, kbdStateAddr$, kbdIndex$
  tiraWriteMem kbdStateAddr$, "1", "1"

  lblMapDone$ = tiraLabelCreateNew$("KD_MAP_DONE")

  lblNotLeft$ = tiraLabelCreateNew$("KD_NOT_LEFT")
  tiraJmpCond "JNE", wParamVal$, "37", lblNotLeft$
  tiraAssign wParamVal$, "52"
  tiraJmp lblMapDone$
  tiraLabel lblNotLeft$

  lblNotUp$ = tiraLabelCreateNew$("KD_NOT_UP")
  tiraJmpCond "JNE", wParamVal$, "38", lblNotUp$
  tiraAssign wParamVal$, "56"
  tiraJmp lblMapDone$
  tiraLabel lblNotUp$

  lblNotRight$ = tiraLabelCreateNew$("KD_NOT_RIGHT")
  tiraJmpCond "JNE", wParamVal$, "39", lblNotRight$
  tiraAssign wParamVal$, "54"
  tiraJmp lblMapDone$
  tiraLabel lblNotRight$

  lblNotDown$ = tiraLabelCreateNew$("KD_NOT_DOWN")
  tiraJmpCond "JNE", wParamVal$, "40", lblNotDown$
  tiraAssign wParamVal$, "50"
  tiraJmp lblMapDone$
  tiraLabel lblNotDown$

  tiraJmp lblOnDefault$

  tiraLabel lblMapDone$

  ' Fall through to .onChar:
  tiraLabel lblOnChar$

  charHeadPtr$ = tiraStackVar$("CHAR_HEAD_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_CHAR_HEAD_PTR)
  charHeadVal$ = tiraStackVar$("CHAR_HEAD_VAL", TYPE_LONG, stack.WNDPROC_SLOT_CHAR_HEAD_VAL)
  charNextHead$ = tiraStackVar$("CHAR_NEXTHEAD", TYPE_LONG, stack.WNDPROC_SLOT_CHAR_NEXTHEAD)
  charTailPtr$ = tiraStackVar$("CHAR_TAIL_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_CHAR_TAIL_PTR)
  charTailVal$ = tiraStackVar$("CHAR_TAIL_VAL", TYPE_LONG, stack.WNDPROC_SLOT_CHAR_TAIL_VAL)
  charBufPtr$ = tiraStackVar$("CHAR_BUF_PTR", TYPE_INTEGER64, stack.WNDPROC_SLOT_CHAR_BUF_PTR)
  charTarget$ = tiraStackVar$("CHAR_TARGET", TYPE_INTEGER64, stack.WNDPROC_SLOT_CHAR_TARGET)

  tiraOp TC_ADDRESS_OF, charHeadPtr$, "!G_LAYOUT_KBD_HEAD_VAL", ""
  tiraNew TC_READ_MEM, charHeadVal$ + ", " + charHeadPtr$

  tiraOp TC_ADD, charNextHead$, charHeadVal$, "1"
  tiraOp TC_AND, charNextHead$, charNextHead$, "255"

  tiraOp TC_ADDRESS_OF, charTailPtr$, "!G_LAYOUT_KBD_TAIL_VAL", ""
  tiraNew TC_READ_MEM, charTailVal$ + ", " + charTailPtr$

  lblOnCharEnd$ = tiraLabelCreateNew$("WND_CHAR_END")
  tiraJmpCond "JE", charNextHead$, charTailVal$, lblOnCharEnd$

  tiraOp TC_ADDRESS_OF, charBufPtr$, "!G_LAYOUT_KBD_BUF_ARR", ""
  tiraOp TC_ADD, charTarget$, charBufPtr$, charHeadVal$

  tiraWriteMem charTarget$, wParamVal$, "1"
  tiraWriteMem charHeadPtr$, charNextHead$, "4"

  tiraLabel lblOnCharEnd$

  tiraAssign retVal$, "0"
  tiraNew TC_ABI_WRITE_RET, retVal$
  tiraNew TC_ABI_EPILOGUE, LTRIM$(STR$(stack.GFX_WNDPROC_FRAME))

  ' .onKeyUp:
  tiraLabel lblOnKeyUp$

  kbdIndexUp$ = tiraStackVar$("KBD_IDX_UP", TYPE_LONG, stack.WNDPROC_SLOT_MAPPED_KEY)
  tiraOp TC_AND, kbdIndexUp$, wParamVal$, "255"
  kbdStateAddrUp$ = tiraStackVar$("KBD_STATE_ADDR_UP", TYPE_INTEGER64, stack.WNDPROC_SLOT_KEY_STATE)
  tiraOp TC_ADDRESS_OF, kbdStateAddrUp$, "!G_LAYOUT_KBD_STATE_ARR", ""
  tiraOp TC_ADD, kbdStateAddrUp$, kbdStateAddrUp$, kbdIndexUp$
  tiraWriteMem kbdStateAddrUp$, "0", "1"

  tiraJmp lblOnDefault$

  ' .onMouse:
  tiraLabel lblOnMouse$

  pointVar$ = tiraStackVar$("POINT", TYPE_INTEGER64, stack.WNDPROC_SLOT_PIX_B)
  pointPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, pointPtr$, pointVar$, ""

  tiraCall "IAT_GETCURSORPOS", 1, pointPtr$
  tiraCall "IAT_SCREENTOCLIENT", 2, hwndVar$ + ", " + pointPtr$

  mouseX$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, mouseX$ + ", " + pointPtr$ + ", 0"
  mouseY$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, mouseY$ + ", " + pointPtr$ + ", 4"

  tiraOp TC_MUL, mouseX$, mouseX$, LTRIM$(STR$(gfxConfig.SizeX))
  tiraOp TC_IDIV, mouseX$, mouseX$, "!G_LAYOUT_WINDOW_W_VAL"
  tiraOp TC_MUL, mouseY$, mouseY$, LTRIM$(STR$(gfxConfig.SizeY))
  tiraOp TC_IDIV, mouseY$, mouseY$, "!G_LAYOUT_WINDOW_H_VAL"

  mouseWheel$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign mouseWheel$, "0"

  mouseBtns$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign mouseBtns$, wParamVal$

  skipWheelLbl$ = tiraLabelCreateNew$("SKIP_WHEEL")
  tiraJmpCond "JNE", msgVal$, "522", skipWheelLbl$

  tiraOp TC_SHR, mouseWheel$, wParamVal$, "16"
  lblNotNegWheel$ = tiraLabelCreateNew$("WHEEL_POS")
  tiraJmpCond "JL", mouseWheel$, "32768", lblNotNegWheel$
  tiraOp TC_SUB, mouseWheel$, mouseWheel$, "65536"
  tiraLabel lblNotNegWheel$
  tiraOp TC_IDIV, mouseWheel$, mouseWheel$, "120"

  tiraOp TC_AND, mouseBtns$, wParamVal$, "65535"

  tiraLabel skipWheelLbl$

  b1$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, b1$, mouseBtns$, "1"
  b2$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, b2$, mouseBtns$, "2"
  b3$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, b3$, mouseBtns$, "16"
  tiraOp TC_SHR, b3$, b3$, "2"

  finalBtns$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_OR, finalBtns$, b1$, b2$
  tiraOp TC_OR, finalBtns$, finalBtns$, b3$

  headPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, headPtr$, "!G_LAYOUT_MOUSE_HEAD_VAL", ""
  headVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, headVal$ + ", " + headPtr$

  nextHead$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, nextHead$, headVal$, "1"
  tiraOp TC_AND, nextHead$, nextHead$, "511"

  tailPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, tailPtr$, "!G_LAYOUT_MOUSE_TAIL_VAL", ""
  tailVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, tailVal$ + ", " + tailPtr$

  skipMouseEnd$ = tiraLabelCreateNew$("MOUSE_BUF_FULL")
  tiraJmpCond "JE", nextHead$, tailVal$, skipMouseEnd$

  bufArrPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, bufArrPtr$, "!G_LAYOUT_MOUSE_BUF_ARR", ""

  offsetVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, offsetVal$, headVal$, "16"

  recPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, recPtr$, bufArrPtr$, offsetVal$

  tiraWriteMem recPtr$, mouseX$, "4"
  tiraNew TC_WRITE_MEM_OFFSET, recPtr$ + ", 4, " + mouseY$ + ", 4"
  tiraNew TC_WRITE_MEM_OFFSET, recPtr$ + ", 8, " + mouseWheel$ + ", 4"
  tiraNew TC_WRITE_MEM_OFFSET, recPtr$ + ", 12, " + finalBtns$ + ", 4"

  tiraWriteMem headPtr$, nextHead$, "4"

  tiraLabel skipMouseEnd$
  tiraJmp lblOnDefault$

  tiraLabel lblUser$

  lblSpinTop$ = tiraLabelCreateNew$("SPIN_TOP")
  lblSpinEnd$ = tiraLabelCreateNew$("SPIN_END")
  tiraLabel lblSpinTop$
  tiraJmpCond "JNE", "!G_WND_READY_FLAG", "0", lblSpinEnd$
  tiraCall "IAT_SLEEP", 1, "1"
  tiraJmp lblSpinTop$
  tiraLabel lblSpinEnd$

  tira_EndAndProcess

END SUB ' emitPrologueWindowSetup

''''''''''''''''''''''''
SUB emitRuntimeAll

  ' Some runtime routines rely on other smaller helpers to do their job
  ' We flag those required helpers here so they get compiled into the executable
  IF rtIsUsed(RT_LINE) = 1 THEN rtIsUsed(RT_PLOT_PIXEL) = 1
  IF rtIsUsed(RT_CIRCLE) = 1 THEN rtIsUsed(RT_PLOT_PIXEL) = 1
  IF rtIsUsed(RT_VEH_HANDLER) = 1 THEN
    rtIsUsed(RT_PRINT_STR) = 1
    rtIsUsed(RT_CRLF) = 1
  END IF
  IF rtIsUsed(RT_INPUT) = 1 THEN
    rtIsUsed(RT_STR_ASSIGN) = 1
    rtIsUsed(RT_CRLF) = 1
    IF compileHasGraphics = 0 THEN
      rtIsUsed(RT_PRINT_STR) = 1
    ELSE
      rtIsUsed(RT_GFX_APPEND) = 1
    END IF
  END IF
  IF rtIsUsed(RT_READ) = 1 THEN
    rtIsUsed(RT_STR_ASSIGN) = 1
    rtIsUsed(RT_PRINT_STR) = 1
    rtIsUsed(RT_CRLF) = 1
  END IF

  IF compileHasGraphics = 1 THEN
    IF rtIsUsed(RT_PRINT_INT) = 1 THEN rtIsUsed(RT_GFX_APPEND) = 1
    IF rtIsUsed(RT_PRINT_FLOAT) = 1 THEN rtIsUsed(RT_GFX_APPEND) = 1
    IF rtIsUsed(RT_PRINT_STR) = 1 THEN rtIsUsed(RT_GFX_APPEND) = 1
    IF rtIsUsed(RT_AUTODISPLAY_CHECK) = 1 THEN rtIsUsed(RT_SWAP_BUFFERS) = 1
  END IF

  tira_Start
  tiraJmp "@SKIP_RUNTIME"
  tira_EndAndProcess

  ' Arm the runtime phase and verify the wrapper is defaulted to OFF
  isCompilingRT = 1
  rtWrapperActive = 0

  IF rtIsUsed(RT_STR_ASSIGN) = 1 THEN emitRuntimeStrAssign
  IF rtIsUsed(RT_PLOT_PIXEL) = 1 THEN emitRuntimePlotPixel
  IF rtIsUsed(RT_LINE) = 1 THEN emitRuntimeLine
  IF rtIsUsed(RT_CIRCLE) = 1 THEN emitRuntimeCircle
  IF rtIsUsed(RT_VEH_HANDLER) = 1 THEN emitRuntimeVehHandler
  IF rtIsUsed(RT_KEYDOWN) = 1 THEN emitRuntimeKeyDown

  ' Embed the additional I/O runtime helpers
  IF rtIsUsed(RT_PRINT_INT) = 1 THEN emitRuntimePrintInt
  IF rtIsUsed(RT_PRINT_FLOAT) = 1 THEN emitRuntimePrintFloat
  IF rtIsUsed(RT_PRINT_STR) = 1 THEN emitRuntimePrintStr
  IF rtIsUsed(RT_CRLF) = 1 THEN emitRuntimeCrlf
  IF rtIsUsed(RT_INPUT) = 1 THEN emitRuntimeInput
  IF rtIsUsed(RT_STR_CMP) = 1 THEN emitRuntimeStrCmp
  IF rtIsUsed(RT_READ) = 1 THEN emitRuntimeRead

  IF compileHasGraphics = 1 THEN
    IF rtIsUsed(RT_GFX_APPEND) = 1 THEN emitRuntimeGfxAppend
    IF rtIsUsed(RT_GET) = 1 THEN emitRuntimeGfxGet
    IF rtIsUsed(RT_PUT) = 1 THEN emitRuntimeGfxPut
    IF rtIsUsed(RT_SWAP_BUFFERS) = 1 THEN emitRuntimeSwapBuffers
    IF rtIsUsed(RT_FULLSCREEN) = 1 THEN emitRuntimeFullscreen
    IF rtIsUsed(RT_AUTODISPLAY_CHECK) = 1 THEN emitRuntimeAutodisplayCheck
    IF rtIsUsed(RT_MOUSEINPUT) = 1 THEN emitRuntimeMouseInput
  END IF

  ' Deactivate the runtime phase to allow normal execution loops to resume
  isCompilingRT = 0

  tira_Start
  tiraLabel "@SKIP_RUNTIME"
  tira_EndAndProcess

END SUB ' emitRuntimeAll

''''''''''''''''''''''''
SUB emitRuntimeAutodisplayCheck

  rtOffset(RT_AUTODISPLAY_CHECK) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  skipDisplayILbl$ = tiraLabelCreateNew$("SKIP_DISPLAYI")

  ' Check if pending flag is 0
  tiraJmpCond "JE", "!G_GFX_DISPLAYI_PENDING_FLAG", "0", skipDisplayILbl$

  ' Get Tick Count from Windows
  tiraCall "IAT_GETTICKCOUNT", 0, ""
  curTick$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, curTick$

  ' Calculate time elapsed since last refresh
  diffTick$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, diffTick$, curTick$, "!G_GFX_DISPLAYI_TIMER_VAL"

  ' If less than 16 milliseconds have passed, skip the redraw to enforce 60 FPS maximum
  tiraJmpCond "JL", diffTick$, "16", skipDisplayILbl$

  ' Trigger the buffer swap to push the backbuffer to the monitor
  tiraCall "RT_SWAP_BUFFERS", 0, ""

  ' Reset the pending flag and update the timer
  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "0"
  tiraAssign "!G_GFX_DISPLAYI_TIMER_VAL", curTick$

  tiraLabel skipDisplayILbl$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeAutodisplayCheck

''''''''''''''''''''''''
SUB emitRuntimeCircle

  rtOffset(RT_CIRCLE) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  argCx$ = tiraDimVar$("ARG1", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argCx$ + ", 1"
  argCy$ = tiraDimVar$("ARG2", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argCy$ + ", 2"
  argR$ = tiraDimVar$("ARG3", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argR$ + ", 3"
  argC$ = tiraDimVar$("ARG4", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argC$ + ", 4"

  x$ = tiraDimVar$("T", TYPE_LONG)
  y$ = tiraDimVar$("T", TYPE_LONG)
  errVal$ = tiraDimVar$("T", TYPE_LONG)

  tiraAssign x$, argR$
  tiraAssign y$, "0"
  tiraOp TC_SUB, errVal$, "1", x$

  loopTop$ = tiraLabelCreateNew$("CIRC_LOOP")
  loopDone$ = tiraLabelCreateNew$("CIRC_DONE")

  tiraLabel loopTop$
  tiraJmpCond "JL", x$, y$, loopDone$

  tmpX$ = tiraDimVar$("T", TYPE_LONG)
  tmpY$ = tiraDimVar$("T", TYPE_LONG)

  tiraOp TC_ADD, tmpX$, argCx$, x$
  tiraOp TC_ADD, tmpY$, argCy$, y$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_ADD, tmpX$, argCx$, y$
  tiraOp TC_ADD, tmpY$, argCy$, x$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_SUB, tmpX$, argCx$, y$
  tiraOp TC_ADD, tmpY$, argCy$, x$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_SUB, tmpX$, argCx$, x$
  tiraOp TC_ADD, tmpY$, argCy$, y$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_SUB, tmpX$, argCx$, x$
  tiraOp TC_SUB, tmpY$, argCy$, y$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_SUB, tmpX$, argCx$, y$
  tiraOp TC_SUB, tmpY$, argCy$, x$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_ADD, tmpX$, argCx$, y$
  tiraOp TC_SUB, tmpY$, argCy$, x$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_ADD, tmpX$, argCx$, x$
  tiraOp TC_SUB, tmpY$, argCy$, y$
  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", " + argC$

  tiraOp TC_ADD, y$, y$, "1"

  lblErrPos$ = tiraLabelCreateNew$("CIRC_ERR_POS")
  tiraJmpCond "JGE", errVal$, "0", lblErrPos$

  tmpErr$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, tmpErr$, y$, "2"
  tiraOp TC_ADD, tmpErr$, tmpErr$, "1"
  tiraOp TC_ADD, errVal$, errVal$, tmpErr$
  tiraJmp loopTop$

  tiraLabel lblErrPos$
  tiraOp TC_SUB, x$, x$, "1"

  tmpErr1$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, tmpErr1$, y$, x$
  tiraOp TC_ADD, tmpErr1$, tmpErr1$, "1"
  tiraOp TC_MUL, tmpErr1$, tmpErr1$, "2"
  tiraOp TC_ADD, errVal$, errVal$, tmpErr1$
  tiraJmp loopTop$

  tiraLabel loopDone$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeCircle

''''''''''''''''''''''''
SUB emitRuntimeCrlf

  rtOffset(RT_CRLF) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  IF compileHasGraphics = 0 THEN
    ' Use a strict TYPE_LONG variable to pass -11 to guarantee 32-bit parameter size - Windows specific value for STD_OUTPUT_HANDLE (Standard Output / The Console Screen)
    stdOutConst$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign stdOutConst$, "-11"

    ' Call Windows API to get the standard output handle
    tiraCall "IAT_GETSTDHANDLE", 1, stdOutConst$
    ' Retrieve the returned handle into a temporary variable
    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_GET_RET, hndVar$

    ' The value of the string variable !G_IO_CRLF_DESC$ is its descriptor pointer
    descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraAssign descPtr$, "!G_IO_CRLF_DESC$"

    ' Read the memory address and length of the string data from the descriptor
    strData$ = tiraGetStringData$(descPtr$)
    strLen$ = tiraGetStringLen$(descPtr$)

    ' Provide a safe throwaway memory address for the bytes written output
    numWrt$ = tiraDimVar$("T", TYPE_LONG)
    numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

    ' Write the CRLF string to the console
    tiraCall "IAT_WRITEFILE", 5, hndVar$ + ", " + strData$ + ", " + strLen$ + ", " + numWrtPtr$ + ", 0"
  ELSE
    ' Graphics mode newline logic
    tiraAssign "!G_GFX_CUR_X_VAL", "0"
    tiraOp TC_ADD, "!G_GFX_CUR_Y_VAL", "!G_GFX_CUR_Y_VAL", "8"
  END IF

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeCrlf

''''''''''''''''''''''''
SUB emitRuntimeFullscreen

  rtOffset(RT_FULLSCREEN) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  ' GetSystemMetrics(SM_CXSCREEN = 0)
  tiraCall "IAT_GETSYSTEMMETRICS", 1, "0"
  tiraNew TC_GET_RET, "!G_LAYOUT_WINDOW_W_VAL"

  ' GetSystemMetrics(SM_CYSCREEN = 1)
  tiraCall "IAT_GETSYSTEMMETRICS", 1, "1"
  tiraNew TC_GET_RET, "!G_LAYOUT_WINDOW_H_VAL"

  ' SetWindowLongA(HWND, GWL_STYLE = -16, WS_POPUP | WS_VISIBLE = -1879048192)
  tiraCall "IAT_SETWINDOWLONGA", 3, "!G_LAYOUT_HWND_VAL, -16, -1879048192"

  ' SetWindowPos(HWND, HWND_TOP = 0, 0, 0, cx, cy, SWP_SHOWWINDOW | SWP_FRAMECHANGED = 96)
  tiraCall "IAT_SETWINDOWPOS", 7, "!G_LAYOUT_HWND_VAL, 0, 0, 0, !G_LAYOUT_WINDOW_W_VAL, !G_LAYOUT_WINDOW_H_VAL, 96"

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeFullscreen

''''''''''''''''''''''''
SUB emitRuntimeGfxAppend

  rtOffset(RT_GFX_APPEND) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"
  arg2Var$ = tiraDimVar$("ARG2", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg2Var$ + ", 2"

  '''' Check if buffer is full
  lblNoBufShift$ = tiraLabelCreateNew$("NO_BUF_SHIFT")
  tiraJmpCond "JL", "!G_GFX_BUF_COUNT_BACK_VAL", LTRIM$(STR$(GFX_BUFFER_ENTRIES)), lblNoBufShift$

  gfxBuf$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign gfxBuf$, "!G_GFX_BUF_BACK_PTR"

  srcBuf$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, srcBuf$, gfxBuf$, LTRIM$(STR$(layout.GfxBufEntrySize))

  lenBuf$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign lenBuf$, LTRIM$(STR$((GFX_BUFFER_ENTRIES - 1) * layout.GfxBufEntrySize))

  tiraMemcpy gfxBuf$, srcBuf$, lenBuf$

  tiraAssign "!G_GFX_BUF_COUNT_BACK_VAL", LTRIM$(STR$(GFX_BUFFER_ENTRIES - 1))

  tiraLabel lblNoBufShift$

  '''' Check if !G_GFX_CUR_Y_VAL >= Bottom Row
  botY$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign botY$, LTRIM$(STR$((gfxConfig.SizeY \ 8) * 8))

  lblScrollLoop$ = tiraLabelCreateNew$("SCROLL_LOOP")
  tiraLabel lblScrollLoop$

  lblNoScreenScroll$ = tiraLabelCreateNew$("NO_SCREEN_SCROLL")
  tiraJmpCond "JL", "!G_GFX_CUR_Y_VAL", botY$, lblNoScreenScroll$

  fbBase$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign fbBase$, "!G_FRAMEBUF_BACK_PTR"

  fbRowBytes$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign fbRowBytes$, LTRIM$(STR$(8 * gfxConfig.SizeX))

  srcFb$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, srcFb$, fbBase$, fbRowBytes$

  fbShiftRows$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, fbShiftRows$, botY$, "8"
  fbShiftCount$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, fbShiftCount$, fbShiftRows$, LTRIM$(STR$(gfxConfig.SizeX))

  tiraMemcpy fbBase$, srcFb$, fbShiftCount$

  botRowPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, botRowPtr$, fbBase$, fbShiftCount$
  tiraMemSet botRowPtr$, "0", fbRowBytes$

  lblSkipTextShift$ = tiraLabelCreateNew$("SKIP_TEXT_SHIFT")
  tiraJmpCond "JE", "!G_GFX_BUF_COUNT_BACK_VAL", "0", lblSkipTextShift$

  itrText$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign itrText$, "!G_GFX_BUF_BACK_PTR"

  itrCount$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign itrCount$, "!G_GFX_BUF_COUNT_BACK_VAL"

  lblTextShiftLoop$ = tiraLabelCreateNew$("TEXT_SHIFT_LOOP")
  tiraLabel lblTextShiftLoop$

  textYPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, textYPtr$, itrText$, "20"
  textY$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, textY$ + ", " + textYPtr$

  lblSkipThisText$ = tiraLabelCreateNew$("SKIP_THIS_TEXT")
  tiraJmpCond "JL", textY$, "0", lblSkipThisText$
  tiraJmpCond "JGE", textY$, botY$, lblSkipThisText$

  tiraOp TC_SUB, textY$, textY$, "8"
  tiraWriteMem textYPtr$, textY$, "4"

  tiraLabel lblSkipThisText$

  tiraOp TC_ADD, itrText$, itrText$, LTRIM$(STR$(layout.GfxBufEntrySize))
  tiraOp TC_SUB, itrCount$, itrCount$, "1"
  tiraJmpCond "JG", itrCount$, "0", lblTextShiftLoop$

  tiraLabel lblSkipTextShift$

  tiraOp TC_SUB, "!G_GFX_CUR_Y_VAL", "!G_GFX_CUR_Y_VAL", "8"
  tiraJmp lblScrollLoop$

  tiraLabel lblNoScreenScroll$

  '''' Append new text entry
  entryOffset$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, entryOffset$, "!G_GFX_BUF_COUNT_BACK_VAL", LTRIM$(STR$(layout.GfxBufEntrySize))

  entryPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign entryPtr$, "!G_GFX_BUF_BACK_PTR"
  tiraOp TC_ADD, entryPtr$, entryPtr$, entryOffset$

  textXPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, textXPtr$, entryPtr$, "16"
  tiraWriteMem textXPtr$, "!G_GFX_CUR_X_VAL", "4"

  lenPixels$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, lenPixels$, arg2Var$, "8"
  tiraOp TC_ADD, "!G_GFX_CUR_X_VAL", "!G_GFX_CUR_X_VAL", lenPixels$

  newTextYPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, newTextYPtr$, entryPtr$, "20"
  tiraWriteMem newTextYPtr$, "!G_GFX_CUR_Y_VAL", "4"

  payloadPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, payloadPtr$, entryPtr$, "24"
  tiraMemcpy payloadPtr$, arg1Var$, arg2Var$

  newLenPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, newLenPtr$, entryPtr$, LTRIM$(STR$(GFX_ENTRY_LEN_OFFSET))
  tiraWriteMem newLenPtr$, arg2Var$, "4"

  colorPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, colorPtr$, entryPtr$, "12"
  tiraWriteMem colorPtr$, "!G_GFX_FG_VAL", "4"

  tiraOp TC_ADD, "!G_GFX_BUF_COUNT_BACK_VAL", "!G_GFX_BUF_COUNT_BACK_VAL", "1"

  '''' Redraw Graphic Viewport
  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraRT_Epilogue

  tira_EndAndProcess

END SUB ' emitRuntimeGfxAppend

''''''''''''''''''''''''
SUB emitRuntimeGfxGet

  rtOffset(RT_GET) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  argX1$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argX1$ + ", 1"
  argY1$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argY1$ + ", 2"
  argX2$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argX2$ + ", 3"
  argY2$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, argY2$ + ", 4"
  argPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, argPtr$ + ", 5"
  argEnd$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, argEnd$ + ", 6"

  ' Swap X bounds if X1 > X2
  ptr1$ = tiraDimVar$("T", TYPE_INTEGER64)
  ptr2$ = tiraDimVar$("T", TYPE_INTEGER64)

  skipXSwap$ = tiraLabelCreateNew$("GET_SKIP_X")
  tiraJmpCond "JLE", argX1$, argX2$, skipXSwap$
  tiraOp TC_ADDRESS_OF, ptr1$, argX1$, ""
  tiraOp TC_ADDRESS_OF, ptr2$, argX2$, ""
  tiraSwapMem ptr1$, ptr2$, "4"
  tiraLabel skipXSwap$

  ' Swap Y bounds if Y1 > Y2
  skipYSwap$ = tiraLabelCreateNew$("GET_SKIP_Y")
  tiraJmpCond "JLE", argY1$, argY2$, skipYSwap$
  tiraOp TC_ADDRESS_OF, ptr1$, argY1$, ""
  tiraOp TC_ADDRESS_OF, ptr2$, argY2$, ""
  tiraSwapMem ptr1$, ptr2$, "4"
  tiraLabel skipYSwap$

  ' Calculate array width metrics into width$
  width$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, width$, argX2$, argX1$
  tiraOp TC_ADD, width$, width$, "1"

  ' Calculate array height metrics into height$
  height$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, height$, argY2$, argY1$
  tiraOp TC_ADD, height$, height$, "1"

  ' Perform an Array Bounds Limit Check to ensure we have enough space for the header
  chkPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, chkPtr$, argPtr$, "8"
  doneLbl$ = tiraLabelCreateNew$("GET_DONE")
  tiraJmpCond "JG", chkPtr$, argEnd$, doneLbl$

  ' Directly embed our dimensional metrics into the array structure exactly like native QBasic
  tiraWriteMem argPtr$, width$, "4"

  heightPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, heightPtr$, argPtr$, "4"
  tiraWriteMem heightPtr$, height$, "4"

  tiraOp TC_ADD, argPtr$, argPtr$, "8"

  ' Fetch Framebuffer Base from user working buffer
  fbBase$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign fbBase$, "!G_FRAMEBUF_BACK_PTR"

  ' Execute outer rendering loop tracking Y iterations
  iterY$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign iterY$, argY1$

  loopY$ = tiraLabelCreateNew$("GET_LOOP_Y")
  tiraLabel loopY$
  tiraJmpCond "JG", iterY$, argY2$, doneLbl$

  ' Execute inner rendering loop tracking X iterations
  iterX$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign iterX$, argX1$

  loopX$ = tiraLabelCreateNew$("GET_LOOP_X")
  tiraLabel loopX$
  endXLbl$ = tiraLabelCreateNew$("GET_END_X")
  tiraJmpCond "JG", iterX$, argX2$, endXLbl$

  ' Clip boundaries to prevent reading outside the physical window coordinates
  pixel$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign pixel$, "0"

  skipBounds$ = tiraLabelCreateNew$("GET_SKIP_BND")
  ' Speed boost optimization: Unsigned JAE bounds check validates both < 0 and >= max simultaneously
  tiraJmpCond "JAE", iterX$, cTrNum$(gfxConfig.SizeX), skipBounds$
  tiraJmpCond "JAE", iterY$, cTrNum$(gfxConfig.SizeY), skipBounds$

  ' Scan pixel byte from memory safely within visual area
  offset$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, offset$, iterY$, cTrNum$(gfxConfig.SizeX)
  tiraOp TC_ADD, offset$, offset$, iterX$

  pixAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, pixAddr$, fbBase$, offset$

  pixel8$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, pixel8$ + ", " + pixAddr$
  tiraAssign pixel$, pixel8$

  tiraLabel skipBounds$

  ' Copy scanned value into memory array structure with protective constraints
  skipWrite$ = tiraLabelCreateNew$("GET_SKIP_WR")
  tiraJmpCond "JGE", argPtr$, argEnd$, skipWrite$
  tiraWriteMem argPtr$, pixel$, "1"
  tiraOp TC_ADD, argPtr$, argPtr$, "1"
  tiraLabel skipWrite$

  ' X++
  tiraOp TC_ADD, iterX$, iterX$, "1"
  tiraJmp loopX$

  ' Y++
  tiraLabel endXLbl$
  tiraOp TC_ADD, iterY$, iterY$, "1"
  tiraJmp loopY$

  tiraLabel doneLbl$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeGfxGet

''''''''''''''''''''''''
SUB emitRuntimeGfxPut

  rtOffset(RT_PUT) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"
  arg2Var$ = tiraDimVar$("ARG2", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg2Var$ + ", 2"
  arg3Var$ = tiraDimVar$("ARG3", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg3Var$ + ", 3"
  arg4Var$ = tiraDimVar$("ARG4", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg4Var$ + ", 4"

  argX$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign argX$, arg1Var$
  argY$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign argY$, arg2Var$
  ptr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign ptr$, arg3Var$
  endPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign endPtr$, arg4Var$

  jmpDonePut1$ = tiraLabelCreateNew$("PUT_DONE1")
  jmpDonePut2$ = tiraLabelCreateNew$("PUT_DONE2")

  ' Check if we have at least 8 bytes available for the array width/height header
  chkPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, chkPtr$, ptr$, "8"
  tiraJmpCond "JG", chkPtr$, endPtr$, jmpDonePut1$

  ' Read width and height natively via TIRA memory indirection
  width$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, width$ + ", " + ptr$

  height$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, height$ + ", " + ptr$ + ", 4"

  tiraOp TC_ADD, ptr$, ptr$, "8"

  fbBase$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign fbBase$, "!G_FRAMEBUF_BACK_PTR"

  iterY$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign iterY$, "0"

  ' Outer Loop Y
  lblLoopY$ = tiraLabelCreateNew$("PUT_LOOP_Y")
  tiraLabel lblLoopY$
  tiraJmpCond "JGE", iterY$, height$, jmpDonePut2$

  iterX$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign iterX$, "0"

  ' Inner Loop X
  lblLoopX$ = tiraLabelCreateNew$("PUT_LOOP_X")
  tiraLabel lblLoopX$

  jmpEndX$ = tiraLabelCreateNew$("PUT_END_X")
  tiraJmpCond "JGE", iterX$, width$, jmpEndX$

  jmpSkipRead$ = tiraLabelCreateNew$("PUT_SKIP_RD")
  tiraJmpCond "JGE", ptr$, endPtr$, jmpSkipRead$

  pixel8$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, pixel8$ + ", " + ptr$
  pixel$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign pixel$, pixel8$

  tiraOp TC_ADD, ptr$, ptr$, "1"

  jmpCheckBounds$ = tiraLabelCreateNew$("PUT_CHK_BND")
  tiraJmp jmpCheckBounds$

  tiraLabel jmpSkipRead$
  tiraAssign pixel$, "0"
  tiraLabel jmpCheckBounds$

  absX$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, absX$, argX$, iterX$
  absY$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, absY$, argY$, iterY$

  jmpSkipDraw$ = tiraLabelCreateNew$("PUT_SKIP_DRW")
  ' Speed boost optimization: Unsigned JAE bounds check validates both < 0 and >= max simultaneously
  tiraJmpCond "JAE", absX$, cTrNum$(gfxConfig.SizeX), jmpSkipDraw$
  tiraJmpCond "JAE", absY$, cTrNum$(gfxConfig.SizeY), jmpSkipDraw$

  offset$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, offset$, absY$, cTrNum$(gfxConfig.SizeX)
  tiraOp TC_ADD, offset$, offset$, absX$

  fbTarget$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, fbTarget$, fbBase$, offset$
  tiraWriteMem fbTarget$, pixel$, "1"

  tiraLabel jmpSkipDraw$

  tiraOp TC_ADD, iterX$, iterX$, "1"
  tiraJmp lblLoopX$

  tiraLabel jmpEndX$
  tiraOp TC_ADD, iterY$, iterY$, "1"
  tiraJmp lblLoopY$

  tiraLabel jmpDonePut1$
  tiraLabel jmpDonePut2$

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeGfxPut

''''''''''''''''''''''''
SUB emitRuntimeInput

  rtOffset(RT_INPUT) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  ' Capture incoming ABI hardware registers into TIRA accessible global memory slots
  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"
  arg2Var$ = tiraDimVar$("ARG2", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg2Var$ + ", 2"
  arg3Var$ = tiraDimVar$("ARG3", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg3Var$ + ", 3"
  arg4Var$ = tiraDimVar$("ARG4", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg4Var$ + ", 4"

  ' Cache the arguments securely to survive nested runtime calls which will clobber the !G_SYS_RT_ARG slots
  targetAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign targetAddrVar$, arg1Var$

  isStrVarVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign isStrVarVar$, arg2Var$

  promptPtrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign promptPtrVar$, arg3Var$

  tgtDataTypeVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign tgtDataTypeVar$, arg4Var$

  ' Allocate a pristine 1024 byte buffer directly on the temporary heap
  bufPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign bufPtr$, "!G_MEM_TEMP_HEAP_PTR"
  tiraOp TC_SUB, bufPtr$, bufPtr$, "1024"
  tiraAssign "!G_MEM_TEMP_HEAP_PTR", bufPtr$

  bufLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign bufLen$, "0"

  IF compileHasGraphics = 0 THEN
    ' Console mode logic
    tiraCall "RT_PRINT_STR", 1, promptPtrVar$

    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraCall "IAT_GETSTDHANDLE", 1, "-10"
    tiraNew TC_GET_RET, hndVar$

    numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, numWrtPtr$, bufLen$, ""

    tiraCall "IAT_READFILE", 5, hndVar$ + ", " + bufPtr$ + ", 1024, " + numWrtPtr$ + ", 0"
  ELSE
    ' Graphics mode logic
    promptData$ = tiraGetStringData$(promptPtrVar$)
    promptLen$ = tiraGetStringLen$(promptPtrVar$)

    tiraMemcpy bufPtr$, promptData$, promptLen$
    tiraAssign bufLen$, promptLen$

    ' Initial draw of the prompt to generate the GfxBuf entry
    tiraCall "RT_GFX_APPEND", 2, bufPtr$ + ", " + bufLen$

    tiraCall "RT_SWAP_BUFFERS", 0, ""

    ' Fetch pointer structures for reading directly from the OS queue
    headPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, headPtr$, "!G_LAYOUT_KBD_HEAD_VAL", ""
    tailPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, tailPtr$, "!G_LAYOUT_KBD_TAIL_VAL", ""

    ' Spinlock: wait for ENTER to be released
    lblWaitEnterRel1$ = tiraLabelCreateNew$("INP_WAIT_REL1")
    tiraLabel lblWaitEnterRel1$
    tiraCall "IAT_GETASYNCKEYSTATE", 1, "13"
    entState1$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_GET_RET, entState1$
    tiraOp TC_AND, entState1$, entState1$, "32768"
    skipSleep1$ = tiraLabelCreateNew$("INP_SS1")
    tiraJmpCond "JE", entState1$, "0", skipSleep1$
    tiraCall "IAT_SLEEP", 1, "1"
    tiraJmp lblWaitEnterRel1$
    tiraLabel skipSleep1$

    ' Flush the OS keyboard ring buffer to clear ghost type-ahead keys completely
    flushHeadVal$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, flushHeadVal$ + ", " + headPtr$
    tiraWriteMem tailPtr$, flushHeadVal$, "4"

    ' Ultra-fast spin loop (No IAT_SLEEP latency penalty)
    loopTop$ = tiraLabelCreateNew$("INP_LOOP")
    tiraLabel loopTop$

    headVal$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, headVal$ + ", " + headPtr$

    tailVal$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, tailVal$ + ", " + tailPtr$

    tiraJmpCond "JE", headVal$, tailVal$, loopTop$

    ' Read Char from the tail
    charBufPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, charBufPtr$, "!G_LAYOUT_KBD_BUF_ARR", ""

    charAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, charAddr$, charBufPtr$, tailVal$

    charByte$ = tiraDimVar$("T", TYPE_UBYTE)
    tiraNew TC_READ_MEM, charByte$ + ", " + charAddr$

    charVal$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign charVal$, charByte$

    ' Advance Tail
    tiraOp TC_ADD, tailVal$, tailVal$, "1"
    tiraOp TC_AND, tailVal$, tailVal$, "255"
    tiraWriteMem tailPtr$, tailVal$, "4"

    doneLbl$ = tiraLabelCreateNew$("INP_DONE")
    tiraJmpCond "JE", charVal$, "13", doneLbl$ ' Enter key finishes the routine

    notBsLbl$ = tiraLabelCreateNew$("INP_NOT_BS")
    tiraJmpCond "JNE", charVal$, "8", notBsLbl$ ' Backspace key

    ' Safely process Backspace and redraw
    skipBsLbl$ = tiraLabelCreateNew$("INP_SKIP_BS")
    tiraJmpCond "JLE", bufLen$, promptLen$, skipBsLbl$
    tiraOp TC_SUB, bufLen$, bufLen$, "1"
    redrawLbl$ = tiraLabelCreateNew$("INP_REDRAW")
    tiraJmp redrawLbl$

    tiraLabel skipBsLbl$
    tiraJmp loopTop$

    tiraLabel notBsLbl$

    ' Only append if printable ASCII (32 to 126)
    skipKey$ = tiraLabelCreateNew$("INP_SKIP")
    tiraJmpCond "JL", charVal$, "32", skipKey$
    tiraJmpCond "JG", charVal$, "126", skipKey$

    destCharAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, destCharAddr$, bufPtr$, bufLen$
    tiraWriteMem destCharAddr$, charVal$, "1"
    tiraOp TC_ADD, bufLen$, bufLen$, "1"

    tiraLabel redrawLbl$

    ' Re-render the entire buffer cleanly into the last GfxBuf entry payload memory
    bufCountSub$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_SUB, bufCountSub$, "!G_GFX_BUF_COUNT_BACK_VAL", "1"
    tiraOp TC_SHL, bufCountSub$, bufCountSub$, LTRIM$(STR$(layout.GfxBufEntryShift))

    lastEntry$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraAssign lastEntry$, "!G_GFX_BUF_BACK_PTR"
    tiraOp TC_ADD, lastEntry$, lastEntry$, bufCountSub$

    entryLenAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, entryLenAddr$, lastEntry$, LTRIM$(STR$(GFX_ENTRY_LEN_OFFSET))
    tiraWriteMem entryLenAddr$, bufLen$, "4"

    entryDataAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, entryDataAddr$, lastEntry$, "24"
    tiraMemcpy entryDataAddr$, bufPtr$, bufLen$

    tiraCall "RT_SWAP_BUFFERS", 0, ""

    tiraLabel skipKey$
    tiraJmp loopTop$

    tiraLabel doneLbl$

    ' Spinlock: wait for ENTER to be released after submitting input
    lblWaitEnterRel2$ = tiraLabelCreateNew$("INP_WAIT_REL2")
    tiraLabel lblWaitEnterRel2$
    tiraCall "IAT_GETASYNCKEYSTATE", 1, "13"
    entState2$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_GET_RET, entState2$
    tiraOp TC_AND, entState2$, entState2$, "32768"
    skipSleep2$ = tiraLabelCreateNew$("INP_SS2")
    tiraJmpCond "JE", entState2$, "0", skipSleep2$
    tiraCall "IAT_SLEEP", 1, "1"
    tiraJmp lblWaitEnterRel2$
    tiraLabel skipSleep2$

    ' Step out of the prompt cleanly for string assignment
    tiraOp TC_ADD, bufPtr$, bufPtr$, promptLen$
    tiraOp TC_SUB, bufLen$, bufLen$, promptLen$

    tiraCall "RT_CRLF", 0, ""
  END IF

  endInputLbl$ = tiraLabelCreateNew$("INP_END")
  notStrLbl$ = tiraLabelCreateNew$("INP_NOT_STR")

  tiraJmpCond "JE", isStrVarVar$, "0", notStrLbl$

  ' Handle string variable assignment
  stripLoop$ = tiraLabelCreateNew$("INP_STRIP")
  stripDone$ = tiraLabelCreateNew$("INP_STRIP_DONE")

  tiraLabel stripLoop$
  tiraJmpCond "JLE", bufLen$, "0", stripDone$

  lastCharAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, lastCharAddr$, bufPtr$, bufLen$
  tiraOp TC_SUB, lastCharAddr$, lastCharAddr$, "1"
  lastChar$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, lastChar$ + ", " + lastCharAddr$

  isCrLfLbl$ = tiraLabelCreateNew$("INP_ISCRLF")
  tiraJmpCond "JE", lastChar$, "13", isCrLfLbl$
  tiraJmpCond "JNE", lastChar$, "10", stripDone$

  tiraLabel isCrLfLbl$
  tiraOp TC_SUB, bufLen$, bufLen$, "1"
  tiraJmp stripLoop$
  tiraLabel stripDone$

  ' Build a 24-byte fake descriptor dynamically
  rhsDesc$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign rhsDesc$, "!G_MEM_TEMP_HEAP_PTR"
  tiraOp TC_SUB, rhsDesc$, rhsDesc$, "24"
  tiraAssign "!G_MEM_TEMP_HEAP_PTR", rhsDesc$

  tiraBuildStringDescriptor rhsDesc$, bufPtr$, bufLen$, "0"

  tiraCall "RT_STR_ASSIGN", 2, targetAddrVar$ + ", " + rhsDesc$
  tiraJmp endInputLbl$

  ' Handle numeric variable assignment
  tiraLabel notStrLbl$

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, "0"
  isNeg$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign isNeg$, "0"

  skipLoop$ = tiraLabelCreateNew$("INP_NSKIP")
  skipDone$ = tiraLabelCreateNew$("INP_NSKIP_DN")

  tiraLabel skipLoop$
  tiraJmpCond "JLE", bufLen$, "0", skipDone$
  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, byteVal$ + ", " + bufPtr$

  isSpcLbl$ = tiraLabelCreateNew$("INP_ISSPC")
  tiraJmpCond "JE", byteVal$, "32", isSpcLbl$
  tiraJmpCond "JE", byteVal$, "13", isSpcLbl$
  tiraJmpCond "JE", byteVal$, "10", isSpcLbl$
  tiraJmp skipDone$

  tiraLabel isSpcLbl$
  tiraOp TC_ADD, bufPtr$, bufPtr$, "1"
  tiraOp TC_SUB, bufLen$, bufLen$, "1"
  tiraJmp skipLoop$

  tiraLabel skipDone$

  signDone$ = tiraLabelCreateNew$("VAL_SGN_DONE")
  tiraJmpCond "JLE", bufLen$, "0", signDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + bufPtr$
  tiraJmpCond "JNE", byteVal$, "45", signDone$ ' -
  tiraAssign isNeg$, "1"
  tiraOp TC_ADD, bufPtr$, bufPtr$, "1"
  tiraOp TC_SUB, bufLen$, bufLen$, "1"

  tiraLabel signDone$

  numLoopTop$ = tiraLabelCreateNew$("VAL_NUM_LOOP")
  numLoopDone$ = tiraLabelCreateNew$("VAL_NUM_DONE")

  tiraLabel numLoopTop$
  tiraJmpCond "JLE", bufLen$, "0", numLoopDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + bufPtr$

  tiraJmpCond "JL", byteVal$, "48", numLoopDone$ ' 0
  tiraJmpCond "JG", byteVal$, "57", numLoopDone$ ' 9

  tiraOp TC_SUB, byteVal$, byteVal$, "48"
  tiraOp TC_MUL, resVar$, resVar$, "10"
  tiraOp TC_ADD, resVar$, resVar$, byteVal$

  tiraOp TC_ADD, bufPtr$, bufPtr$, "1"
  tiraOp TC_SUB, bufLen$, bufLen$, "1"
  tiraJmp numLoopTop$

  tiraLabel numLoopDone$

  applySignDone$ = tiraLabelCreateNew$("VAL_SGN_APP")
  tiraJmpCond "JE", isNeg$, "0", applySignDone$
  tiraOp TC_NEG, resVar$, resVar$, ""
  tiraLabel applySignDone$

  lblSingle$ = tiraLabelCreateNew$("IS_SNG")
  lblDouble$ = tiraLabelCreateNew$("IS_DBL")
  lblByte$ = tiraLabelCreateNew$("IS_BYT")
  lblInt$ = tiraLabelCreateNew$("IS_INT")
  lblLong$ = tiraLabelCreateNew$("IS_LNG")
  lblWriteDone$ = tiraLabelCreateNew$("WR_DONE")

  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_SINGLE)), lblSingle$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_DOUBLE)), lblDouble$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_BYTE)), lblByte$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_UBYTE)), lblByte$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_INTEGER)), lblInt$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_UINTEGER)), lblInt$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_LONG)), lblLong$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_ULONG)), lblLong$

  tiraWriteMem targetAddrVar$, resVar$, "8"
  tiraJmp lblWriteDone$

  tiraLabel lblSingle$
  tiraWriteMem targetAddrVar$, resVar$, "SINGLE"
  tiraJmp lblWriteDone$

  tiraLabel lblDouble$
  tiraWriteMem targetAddrVar$, resVar$, "DOUBLE"
  tiraJmp lblWriteDone$

  tiraLabel lblByte$
  tiraWriteMem targetAddrVar$, resVar$, "1"
  tiraJmp lblWriteDone$

  tiraLabel lblInt$
  tiraWriteMem targetAddrVar$, resVar$, "2"
  tiraJmp lblWriteDone$

  tiraLabel lblLong$
  tiraWriteMem targetAddrVar$, resVar$, "4"

  tiraLabel lblWriteDone$

  tiraLabel endInputLbl$

  tiraRT_Epilogue

  tira_EndAndProcess

END SUB ' emitRuntimeInput

''''''''''''''''''''''''
SUB emitRuntimeKeyDown

  DIM qb AS LONG
  DIM vk AS LONG

  ' Build the key mapping data as a string payload to sit in the global literal pool
  mapPayload$ = ""
  FOR ii = 0 TO keyMappingCount - 1
    ' Append qbCode (4 bytes)
    qb = keyMapping(ii).qbCode
    mapPayload$ = mapPayload$ + CHR$(qb AND 255) + CHR$((qb \ 256) AND 255) + CHR$((qb \ 65536) AND 255) + CHR$((qb \ 16777216) AND 255)
    ' Append vkCode (4 bytes)
    vk = keyMapping(ii).vkCode
    mapPayload$ = mapPayload$ + CHR$(vk AND 255) + CHR$((vk \ 256) AND 255) + CHR$((vk \ 65536) AND 255) + CHR$((vk \ 16777216) AND 255)
  NEXT

  ff = resolveSymbol("!G_IO_KEYMAP_DESC$")
  IF ff = 1 THEN
    mapIdx = returnedData2
    strVarData$(mapIdx) = mapPayload$
  END IF

  '''' RT_KEYDOWN
  rtOffset(RT_KEYDOWN) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"

  ' Load the requested key code
  qbCode$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign qbCode$, arg1Var$

  ' Extract the data pointer from the string descriptor
  tableDesc$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign tableDesc$, "!G_IO_KEYMAP_DESC$"
  tablePtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, tablePtr$ + ", " + tableDesc$

  ' Counter for mapped items
  count$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign count$, LTRIM$(STR$(keyMappingCount))

  vkCode$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign vkCode$, qbCode$

  loopScanStart$ = tiraLabelCreateNew$("KD_SCAN_LOOP")
  jmpDoneScan$ = tiraLabelCreateNew$("KD_SCAN_DONE")

  tiraLabel loopScanStart$

  ' If mapped items remain <= 0, we're done (not found in table)
  tiraJmpCond "JLE", count$, "0", jmpDoneScan$

  ' Compare table[index].qbCode with the requested code
  curQb$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, curQb$ + ", " + tablePtr$

  jmpFound$ = tiraLabelCreateNew$("KD_FOUND")
  tiraJmpCond "JE", curQb$, qbCode$, jmpFound$

  ' Advance to next 8-byte entry (qbCode + vkCode layout)
  tiraOp TC_ADD, tablePtr$, tablePtr$, "8"
  tiraOp TC_SUB, count$, count$, "1"
  tiraJmp loopScanStart$

  ' Match found, extract table[index].vkCode
  tiraLabel jmpFound$
  vkPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, vkPtr$, tablePtr$, "4"
  tiraNew TC_READ_MEM, vkCode$ + ", " + vkPtr$

  tiraLabel jmpDoneScan$

  ' Setup layout state extraction directly from the WndProc populated array
  tiraOp TC_AND, vkCode$, vkCode$, "255"

  stateAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, stateAddr$, "!G_LAYOUT_KBD_STATE_ARR", ""
  tiraOp TC_ADD, stateAddr$, stateAddr$, vkCode$

  keyByte$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, keyByte$ + ", " + stateAddr$

  keyState$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign keyState$, keyByte$

  retVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign retVal$, "0"

  jmpIsDown$ = tiraLabelCreateNew$("KD_IS_DOWN")
  tiraJmpCond "JNE", keyState$, "0", jmpIsDown$

  ' Not down (return 0)
  jmpEnd$ = tiraLabelCreateNew$("KD_END")
  tiraJmp jmpEnd$

  tiraLabel jmpIsDown$
  ' Is down (return -1)
  tiraAssign retVal$, "-1"

  tiraLabel jmpEnd$

  ' Route return value to arg1Var$ so it can be extracted to RAX cleanly
  tiraAssign arg1Var$, retVal$

  tiraNew TC_ABI_WRITE_RET, arg1Var$
  tiraRT_Epilogue

  tira_EndAndProcess

END SUB ' emitRuntimeKeyDown

''''''''''''''''''''''''
SUB emitRuntimeLine

  '''' RT_LINE
  rtOffset(RT_LINE) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  tmpX$ = tiraDimVar$("T", TYPE_LONG)
  tmpY$ = tiraDimVar$("T", TYPE_LONG)
  errVar$ = tiraDimVar$("T", TYPE_LONG)
  e2Var$ = tiraDimVar$("T", TYPE_LONG)
  tmpPtr1$ = tiraDimVar$("T", TYPE_INTEGER64)
  tmpPtr2$ = tiraDimVar$("T", TYPE_INTEGER64)

  tiraNew TC_ABI_READ_ARG, "!G_GFX_X1_VAL, 1"
  tiraNew TC_ABI_READ_ARG, "!G_GFX_Y1_VAL, 2"
  tiraNew TC_ABI_READ_ARG, "!G_GFX_X2_VAL, 3"
  tiraNew TC_ABI_READ_ARG, "!G_GFX_Y2_VAL, 4"
  tiraNew TC_ABI_READ_ARG, "!G_GFX_COLOR_VAL, 5"
  tiraNew TC_ABI_READ_ARG, "!G_GFX_BOX_FLAG, 6"
  tiraNew TC_ABI_READ_ARG, "!G_GFX_STYLE_VAL, 7"

  lblNotBF$ = tiraLabelCreateNew$("NOT_BF")
  lblEndBF$ = tiraLabelCreateNew$("END_BF")

  ' IF !G_GFX_BOX_FLAG != 2 GOTO NOT_BF
  tiraJmpCond "JNE", "!G_GFX_BOX_FLAG", "2", lblNotBF$

  ' Swap X if X1 > X2
  lblSkipSwapX_BF$ = tiraLabelCreateNew$("SKIP_SWAP_X_BF")
  tiraJmpCond "JLE", "!G_GFX_X1_VAL", "!G_GFX_X2_VAL", lblSkipSwapX_BF$
  tiraOp TC_ADDRESS_OF, tmpPtr1$, "!G_GFX_X1_VAL", ""
  tiraOp TC_ADDRESS_OF, tmpPtr2$, "!G_GFX_X2_VAL", ""
  tiraSwapMem tmpPtr1$, tmpPtr2$, "8"
  tiraLabel lblSkipSwapX_BF$

  ' Swap Y if Y1 > Y2
  lblSkipSwapY_BF$ = tiraLabelCreateNew$("SKIP_SWAP_Y_BF")
  tiraJmpCond "JLE", "!G_GFX_Y1_VAL", "!G_GFX_Y2_VAL", lblSkipSwapY_BF$
  tiraOp TC_ADDRESS_OF, tmpPtr1$, "!G_GFX_Y1_VAL", ""
  tiraOp TC_ADDRESS_OF, tmpPtr2$, "!G_GFX_Y2_VAL", ""
  tiraSwapMem tmpPtr1$, tmpPtr2$, "8"
  tiraLabel lblSkipSwapY_BF$

  ' Outer Loop (Y)
  tiraAssign tmpY$, "!G_GFX_Y1_VAL"
  lblLoopY_BF$ = tiraLabelCreateNew$("LOOP_Y_BF")
  tiraLabel lblLoopY_BF$
  tiraJmpCond "JG", tmpY$, "!G_GFX_Y2_VAL", lblEndBF$

  ' Inner Loop (X)
  tiraAssign tmpX$, "!G_GFX_X1_VAL"
  lblLoopX_BF$ = tiraLabelCreateNew$("LOOP_X_BF")
  lblEndX_BF$ = tiraLabelCreateNew$("END_X_BF")
  tiraLabel lblLoopX_BF$
  tiraJmpCond "JG", tmpX$, "!G_GFX_X2_VAL", lblEndX_BF$

  tiraCall "RT_PLOT_PIXEL", 3, tmpX$ + ", " + tmpY$ + ", !G_GFX_COLOR_VAL"

  tiraOp TC_ADD, tmpX$, tmpX$, "1"
  tiraJmp lblLoopX_BF$
  tiraLabel lblEndX_BF$

  tiraOp TC_ADD, tmpY$, tmpY$, "1"
  tiraJmp lblLoopY_BF$

  tiraLabel lblEndBF$
  lblEndLine$ = tiraLabelCreateNew$("END_LINE")
  tiraJmp lblEndLine$

  tiraLabel lblNotBF$

  ' Box (B) Logic
  lblNotB$ = tiraLabelCreateNew$("NOT_B")
  tiraJmpCond "JNE", "!G_GFX_BOX_FLAG", "1", lblNotB$

  ' Swap X if X1 > X2
  lblSkipSwapX_B$ = tiraLabelCreateNew$("SKIP_SWAP_X_B")
  tiraJmpCond "JLE", "!G_GFX_X1_VAL", "!G_GFX_X2_VAL", lblSkipSwapX_B$
  tiraOp TC_ADDRESS_OF, tmpPtr1$, "!G_GFX_X1_VAL", ""
  tiraOp TC_ADDRESS_OF, tmpPtr2$, "!G_GFX_X2_VAL", ""
  tiraSwapMem tmpPtr1$, tmpPtr2$, "8"
  tiraLabel lblSkipSwapX_B$

  ' Swap Y if Y1 > Y2
  lblSkipSwapY_B$ = tiraLabelCreateNew$("SKIP_SWAP_Y_B")
  tiraJmpCond "JLE", "!G_GFX_Y1_VAL", "!G_GFX_Y2_VAL", lblSkipSwapY_B$
  tiraOp TC_ADDRESS_OF, tmpPtr1$, "!G_GFX_Y1_VAL", ""
  tiraOp TC_ADDRESS_OF, tmpPtr2$, "!G_GFX_Y2_VAL", ""
  tiraSwapMem tmpPtr1$, tmpPtr2$, "8"
  tiraLabel lblSkipSwapY_B$

  ' H1: Y=Y1, X=X1 to X2
  tiraAssign tmpX$, "!G_GFX_X1_VAL"
  lblLoopH1$ = tiraLabelCreateNew$("LOOP_H1")
  lblEndH1$ = tiraLabelCreateNew$("END_H1")
  tiraLabel lblLoopH1$
  tiraJmpCond "JG", tmpX$, "!G_GFX_X2_VAL", lblEndH1$
  tiraBuildStylePlot tmpX$, "!G_GFX_Y1_VAL"
  tiraOp TC_ADD, tmpX$, tmpX$, "1"
  tiraJmp lblLoopH1$
  tiraLabel lblEndH1$

  ' H2: Y=Y2, X=X1 to X2
  tiraAssign tmpX$, "!G_GFX_X1_VAL"
  lblLoopH2$ = tiraLabelCreateNew$("LOOP_H2")
  lblEndH2$ = tiraLabelCreateNew$("END_H2")
  tiraLabel lblLoopH2$
  tiraJmpCond "JG", tmpX$, "!G_GFX_X2_VAL", lblEndH2$
  tiraBuildStylePlot tmpX$, "!G_GFX_Y2_VAL"
  tiraOp TC_ADD, tmpX$, tmpX$, "1"
  tiraJmp lblLoopH2$
  tiraLabel lblEndH2$

  ' V1: X=X1, Y=Y1 to Y2
  tiraAssign tmpY$, "!G_GFX_Y1_VAL"
  lblLoopV1$ = tiraLabelCreateNew$("LOOP_V1")
  lblEndV1$ = tiraLabelCreateNew$("END_V1")
  tiraLabel lblLoopV1$
  tiraJmpCond "JG", tmpY$, "!G_GFX_Y2_VAL", lblEndV1$
  tiraBuildStylePlot "!G_GFX_X1_VAL", tmpY$
  tiraOp TC_ADD, tmpY$, tmpY$, "1"
  tiraJmp lblLoopV1$
  tiraLabel lblEndV1$

  ' V2: X=X2, Y=Y1 to Y2
  tiraAssign tmpY$, "!G_GFX_Y1_VAL"
  lblLoopV2$ = tiraLabelCreateNew$("LOOP_V2")
  lblEndV2$ = tiraLabelCreateNew$("END_V2")
  tiraLabel lblLoopV2$
  tiraJmpCond "JG", tmpY$, "!G_GFX_Y2_VAL", lblEndV2$
  tiraBuildStylePlot "!G_GFX_X2_VAL", tmpY$
  tiraOp TC_ADD, tmpY$, tmpY$, "1"
  tiraJmp lblLoopV2$
  tiraLabel lblEndV2$

  tiraJmp lblEndLine$
  tiraLabel lblNotB$

  ' Bresenham Line Logic
  ' dx
  tiraOp TC_SUB, "!G_GFX_DX_VAL", "!G_GFX_X2_VAL", "!G_GFX_X1_VAL"
  lblSkipNegDX$ = tiraLabelCreateNew$("SKIP_NEG_DX")
  tiraAssign "!G_GFX_SX_VAL", "1"
  tiraJmpCond "JGE", "!G_GFX_DX_VAL", "0", lblSkipNegDX$
  tiraOp TC_NEG, "!G_GFX_DX_VAL", "!G_GFX_DX_VAL", ""
  tiraAssign "!G_GFX_SX_VAL", "-1"
  tiraLabel lblSkipNegDX$

  ' dy
  tiraOp TC_SUB, "!G_GFX_DY_VAL", "!G_GFX_Y2_VAL", "!G_GFX_Y1_VAL"
  lblSkipNegDY$ = tiraLabelCreateNew$("SKIP_NEG_DY")
  tiraAssign "!G_GFX_SY_VAL", "1"
  tiraJmpCond "JGE", "!G_GFX_DY_VAL", "0", lblSkipNegDY$
  tiraOp TC_NEG, "!G_GFX_DY_VAL", "!G_GFX_DY_VAL", ""
  tiraAssign "!G_GFX_SY_VAL", "-1"
  tiraLabel lblSkipNegDY$
  tiraOp TC_NEG, "!G_GFX_DY_VAL", "!G_GFX_DY_VAL", ""

  ' err = dx + dy
  tiraOp TC_ADD, errVar$, "!G_GFX_DX_VAL", "!G_GFX_DY_VAL"

  lblLoopLine$ = tiraLabelCreateNew$("LOOP_LINE")
  tiraLabel lblLoopLine$

  ' Plot
  tiraBuildStylePlot "!G_GFX_X1_VAL", "!G_GFX_Y1_VAL"

  ' Check break
  lblNotDone$ = tiraLabelCreateNew$("NOT_DONE")
  tiraJmpCond "JNE", "!G_GFX_X1_VAL", "!G_GFX_X2_VAL", lblNotDone$
  tiraJmpCond "JE", "!G_GFX_Y1_VAL", "!G_GFX_Y2_VAL", lblEndLine$
  tiraLabel lblNotDone$

  ' e2 = err * 2
  tiraOp TC_MUL, e2Var$, errVar$, "2"

  ' if e2 >= dy
  lblSkipDX$ = tiraLabelCreateNew$("SKIP_DX")
  tiraJmpCond "JL", e2Var$, "!G_GFX_DY_VAL", lblSkipDX$
  tiraOp TC_ADD, errVar$, errVar$, "!G_GFX_DY_VAL"
  tiraOp TC_ADD, "!G_GFX_X1_VAL", "!G_GFX_X1_VAL", "!G_GFX_SX_VAL"
  tiraLabel lblSkipDX$

  ' if e2 <= dx
  lblSkipDY$ = tiraLabelCreateNew$("SKIP_DY")
  tiraJmpCond "JG", e2Var$, "!G_GFX_DX_VAL", lblSkipDY$
  tiraOp TC_ADD, errVar$, errVar$, "!G_GFX_DX_VAL"
  tiraOp TC_ADD, "!G_GFX_Y1_VAL", "!G_GFX_Y1_VAL", "!G_GFX_SY_VAL"
  tiraLabel lblSkipDY$

  tiraJmp lblLoopLine$

  tiraLabel lblEndLine$

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeLine

''''''''''''''''''''''''
SUB emitRuntimeMouseInput

  rtOffset(RT_MOUSEINPUT) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  headPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, headPtr$, "!G_LAYOUT_MOUSE_HEAD_VAL", ""
  headVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, headVal$ + ", " + headPtr$

  tailPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, tailPtr$, "!G_LAYOUT_MOUSE_TAIL_VAL", ""
  tailVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, tailVal$ + ", " + tailPtr$

  retVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign retVal$, "0"

  emptyLbl$ = tiraLabelCreateNew$("MI_EMPTY")
  tiraJmpCond "JE", headVal$, tailVal$, emptyLbl$

  bufArrPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, bufArrPtr$, "!G_LAYOUT_MOUSE_BUF_ARR", ""

  offsetVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, offsetVal$, tailVal$, "16"

  recPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, recPtr$, bufArrPtr$, offsetVal$

  mouseX$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, mouseX$ + ", " + recPtr$
  tiraAssign "!G_IO_MOUSE_X_VAL", mouseX$

  mouseY$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, mouseY$ + ", " + recPtr$ + ", 4"
  tiraAssign "!G_IO_MOUSE_Y_VAL", mouseY$

  mouseWheel$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, mouseWheel$ + ", " + recPtr$ + ", 8"
  tiraAssign "!G_IO_MOUSE_SCRL_VAL", mouseWheel$

  mouseBtns$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, mouseBtns$ + ", " + recPtr$ + ", 12"

  b1$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, b1$, mouseBtns$, "1"
  b1State$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign b1State$, "0"
  skipB1$ = tiraLabelCreateNew$("MI_SKIPB1")
  tiraJmpCond "JE", b1$, "0", skipB1$
  tiraAssign b1State$, "-1"
  tiraLabel skipB1$
  tiraAssign "!G_IO_MOUSE_B1_VAL", b1State$

  b2$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, b2$, mouseBtns$, "2"
  b2State$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign b2State$, "0"
  skipB2$ = tiraLabelCreateNew$("MI_SKIPB2")
  tiraJmpCond "JE", b2$, "0", skipB2$
  tiraAssign b2State$, "-1"
  tiraLabel skipB2$
  tiraAssign "!G_IO_MOUSE_B2_VAL", b2State$

  b3$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, b3$, mouseBtns$, "4"
  b3State$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign b3State$, "0"
  skipB3$ = tiraLabelCreateNew$("MI_SKIPB3")
  tiraJmpCond "JE", b3$, "0", skipB3$
  tiraAssign b3State$, "-1"
  tiraLabel skipB3$
  tiraAssign "!G_IO_MOUSE_B3_VAL", b3State$

  tiraOp TC_ADD, tailVal$, tailVal$, "1"
  tiraOp TC_AND, tailVal$, tailVal$, "511"
  tiraWriteMem tailPtr$, tailVal$, "4"

  tiraAssign retVal$, "-1"

  tiraLabel emptyLbl$

  tiraNew TC_ABI_WRITE_RET, retVal$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeMouseInput

''''''''''''''''''''''''
SUB emitRuntimePlotPixel

  '''' RT_PLOT_PIXEL
  rtOffset(RT_PLOT_PIXEL) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"
  arg2Var$ = tiraDimVar$("ARG2", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg2Var$ + ", 2"
  arg3Var$ = tiraDimVar$("ARG3", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, arg3Var$ + ", 3"

  endLbl$ = tiraLabelCreateNew$("PLOT_END")

  ' Speed boost optimization: Unsigned JAE bounds check validates both < 0 and >= max simultaneously
  tiraJmpCond "JAE", arg1Var$, cTrNum$(gfxConfig.SizeX), endLbl$

  ' Bounds check Y (unsigned)
  tiraJmpCond "JAE", arg2Var$, cTrNum$(gfxConfig.SizeY), endLbl$

  ' Calculate offset
  tiraOp TC_MUL, "!G_GFX_PLOT_OFFSET_IDX", arg2Var$, cTrNum$(gfxConfig.SizeX)
  tiraOp TC_ADD, "!G_GFX_PLOT_OFFSET_IDX", "!G_GFX_PLOT_OFFSET_IDX", arg1Var$

  ' Fetch framebuffer base pointer from the user working buffer safely
  tiraAssign "!G_GFX_PLOT_FBBASE_PTR", "!G_FRAMEBUF_BACK_PTR"

  ' Target address
  tiraOp TC_ADD, "!G_GFX_PLOT_TARGET_PTR", "!G_GFX_PLOT_FBBASE_PTR", "!G_GFX_PLOT_OFFSET_IDX"

  ' Write byte to framebuffer
  tiraWriteMem "!G_GFX_PLOT_TARGET_PTR", arg3Var$, "1"

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  tiraLabel endLbl$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimePlotPixel

''''''''''''''''''''''''
SUB emitRuntimePrintInt

  rtOffset(RT_PRINT_INT) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"

  ' Use !G_MEM_TEMP_HEAP_PTR as the high-end of our temporary string scratchpad.
  ' We do not permanently allocate it because the string is consumed instantly.
  ptr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign ptr$, "!G_MEM_TEMP_HEAP_PTR"

  valVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign valVar$, arg1Var$

  isNeg$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign isNeg$, "0"

  skipNegLbl$ = tiraLabelCreateNew$("PI_SKIP_NEG")
  tiraJmpCond "JGE", valVar$, "0", skipNegLbl$
  tiraAssign isNeg$, "1"
  tiraOp TC_NEG, valVar$, valVar$, ""
  tiraLabel skipNegLbl$

  loopTop$ = tiraLabelCreateNew$("PI_LOOP")
  tiraLabel loopTop$

  ' digit = val MOD 10
  digit$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_MOD, digit$, valVar$, "10"

  divRes$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_IDIV, divRes$, valVar$, "10"

  ' char = digit + 48
  charVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, charVar$, digit$, "48"

  ' ptr = ptr - 1
  tiraOp TC_SUB, ptr$, ptr$, "1"

  ' Write byte to temporary string buffer
  tiraWriteMem ptr$, charVar$, "1"

  ' val = divRes
  tiraAssign valVar$, divRes$

  ' Continue loop if val > 0
  tiraJmpCond "JG", valVar$, "0", loopTop$

  ' Apply negative sign if needed
  skipSignLbl$ = tiraLabelCreateNew$("PI_SKIP_SIGN")
  tiraJmpCond "JE", isNeg$, "0", skipSignLbl$
  tiraOp TC_SUB, ptr$, ptr$, "1"
  tiraWriteMem ptr$, "45", "1" ' 45 is '-'
  tiraLabel skipSignLbl$

  ' Calculate strLen = !G_MEM_TEMP_HEAP_PTR - ptr
  strLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, strLen$, "!G_MEM_TEMP_HEAP_PTR", ptr$

  IF compileHasGraphics = 0 THEN
    ' Console output via WriteFile
    ' Use a strict TYPE_LONG variable to pass -11 to guarantee 32-bit parameter size
    stdOutConst$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign stdOutConst$, "-11"

    ' Call Windows API to get the standard output handle
    tiraCall "IAT_GETSTDHANDLE", 1, stdOutConst$
    ' Retrieve the returned handle into a temporary variable
    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_GET_RET, hndVar$

    ' Provide a safe throwaway memory address for the bytes written output
    numWrt$ = tiraDimVar$("T", TYPE_LONG)
    numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

    ' Write the integer string to the console
    tiraCall "IAT_WRITEFILE", 5, hndVar$ + ", " + ptr$ + ", " + strLen$ + ", " + numWrtPtr$ + ", 0"
  ELSE
    ' Graphics output via GfxAppend
    tiraCall "RT_GFX_APPEND", 2, ptr$ + ", " + strLen$
  END IF

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimePrintInt

''''''''''''''''''''''''
SUB emitRuntimePrintFloat

  rtOffset(RT_PRINT_FLOAT) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_DOUBLE)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"

  ' Allocate 64 bytes on the temporary heap for the sprintf buffer natively
  basePtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign basePtr$, "!G_MEM_TEMP_HEAP_PTR"
  tiraOp TC_SUB, basePtr$, basePtr$, "64"
  tiraAssign "!G_MEM_TEMP_HEAP_PTR", basePtr$

  ' Resolve pointer to the "%g" format string payload
  fmtDesc$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign fmtDesc$, "!G_IO_FMT_G_DESC$"

  fmtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, fmtPtr$ + ", " + fmtDesc$

  ' Call sprintf natively using TIRA. The backend will perfectly mirror the
  ' float variable into both XMM2 and R8 to satisfy the Windows Varargs ABI.
  tiraCall "IAT_SPRINTF", 3, basePtr$ + ", " + fmtPtr$ + ", " + arg1Var$

  ' Capture the return length from sprintf
  strLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, strLen$

  IF compileHasGraphics = 0 THEN
    ' Use a strict TYPE_LONG variable to pass -11 to guarantee 32-bit parameter size
    stdOutConst$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign stdOutConst$, "-11"

    ' Call Windows API to get the standard output handle
    tiraCall "IAT_GETSTDHANDLE", 1, stdOutConst$

    ' Retrieve the returned handle into a temporary variable
    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_GET_RET, hndVar$

    ' Provide a safe throwaway memory address for the bytes written output
    numWrt$ = tiraDimVar$("T", TYPE_LONG)
    numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

    ' Write the float string to the console
    tiraCall "IAT_WRITEFILE", 5, hndVar$ + ", " + basePtr$ + ", " + strLen$ + ", " + numWrtPtr$ + ", 0"
  ELSE
    ' Graphics output via GfxAppend
    tiraCall "RT_GFX_APPEND", 2, basePtr$ + ", " + strLen$
  END IF

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimePrintFloat

''''''''''''''''''''''''
SUB emitRuntimePrintStr

  rtOffset(RT_PRINT_STR) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"

  IF compileHasGraphics = 0 THEN
    ' Use a strict TYPE_LONG variable to pass -11 to guarantee 32-bit parameter size
    stdOutConst$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign stdOutConst$, "-11"

    ' Call Windows API to get the standard output handle
    tiraCall "IAT_GETSTDHANDLE", 1, stdOutConst$

    ' Retrieve the returned handle into a temporary variable
    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_GET_RET, hndVar$

    ' Read the memory address and length of the string data from the descriptor
    strData$ = tiraGetStringData$(arg1Var$)
    strLen$ = tiraGetStringLen$(arg1Var$)

    ' Provide a safe throwaway memory address for the bytes written output
    numWrt$ = tiraDimVar$("T", TYPE_LONG)
    numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

    ' Write the string to the console
    tiraCall "IAT_WRITEFILE", 5, hndVar$ + ", " + strData$ + ", " + strLen$ + ", " + numWrtPtr$ + ", 0"
  ELSE
    ' Graphics mode

    ' Read the memory address and length of the string data from the descriptor
    strData$ = tiraGetStringData$(arg1Var$)
    strLen$ = tiraGetStringLen$(arg1Var$)

    ' Call RT_GFX_APPEND, pass data pointer and length
    tiraCall "RT_GFX_APPEND", 2, strData$ + ", " + strLen$
  END IF

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimePrintStr

''''''''''''''''''''''''
SUB emitRuntimeRead

  rtOffset(RT_READ) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  targetAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, targetAddrVar$ + ", 1"

  isStrVarVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, isStrVarVar$ + ", 2"

  tgtDataTypeVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_ABI_READ_ARG, tgtDataTypeVar$ + ", 3"

  skipErrLbl$ = tiraLabelCreateNew$("READ_SKIP_ERR")
  tiraJmpCond "JL", "!G_SYS_DATA_PTR_VAL", "!G_SYS_DATA_COUNT_VAL", skipErrLbl$

  errStr$ = CHR$(34) + "OUT OF DATA ERROR ON READ" + CHR$(34)
  tiraCall "RT_PRINT_STR", 1, errStr$
  tiraCall "RT_CRLF", 0, ""
  tiraJmp "@END_PROGRAM"

  tiraLabel skipErrLbl$

  baseArr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, baseArr$, "!G_LAYOUT_DATA_PTR_ARR", ""

  descPtrAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraLeaSIB descPtrAddr$, baseArr$, "!G_SYS_DATA_PTR_VAL", "8"

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, descPtr$ + ", " + descPtrAddr$

  tiraOp TC_ADD, "!G_SYS_DATA_PTR_VAL", "!G_SYS_DATA_PTR_VAL", "1"

  notStrLbl$ = tiraLabelCreateNew$("READ_NOT_STR")
  tiraJmpCond "JE", isStrVarVar$, "0", notStrLbl$

  tiraCall "RT_STR_ASSIGN", 2, targetAddrVar$ + ", " + descPtr$

  endReadLbl$ = tiraLabelCreateNew$("READ_END")
  tiraJmp endReadLbl$

  tiraLabel notStrLbl$

  bufPtr$ = tiraGetStringData$(descPtr$)
  bufLen$ = tiraGetStringLen$(descPtr$)

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, "0"
  isNeg$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign isNeg$, "0"

  skipLoop$ = tiraLabelCreateNew$("READ_NSKIP")
  skipDone$ = tiraLabelCreateNew$("READ_NSKIP_DN")

  tiraLabel skipLoop$
  tiraJmpCond "JLE", bufLen$, "0", skipDone$
  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, byteVal$ + ", " + bufPtr$

  isSpcLbl$ = tiraLabelCreateNew$("READ_ISSPC")
  tiraJmpCond "JE", byteVal$, "32", isSpcLbl$
  tiraJmpCond "JE", byteVal$, "13", isSpcLbl$
  tiraJmpCond "JE", byteVal$, "10", isSpcLbl$
  tiraJmp skipDone$

  tiraLabel isSpcLbl$
  tiraOp TC_ADD, bufPtr$, bufPtr$, "1"
  tiraOp TC_SUB, bufLen$, bufLen$, "1"
  tiraJmp skipLoop$

  tiraLabel skipDone$

  signDone$ = tiraLabelCreateNew$("READ_SGN_DONE")
  tiraJmpCond "JLE", bufLen$, "0", signDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + bufPtr$
  tiraJmpCond "JNE", byteVal$, "45", signDone$
  tiraAssign isNeg$, "1"
  tiraOp TC_ADD, bufPtr$, bufPtr$, "1"
  tiraOp TC_SUB, bufLen$, bufLen$, "1"

  tiraLabel signDone$

  numLoopTop$ = tiraLabelCreateNew$("READ_NUM_LOOP")
  numLoopDone$ = tiraLabelCreateNew$("READ_NUM_DONE")

  tiraLabel numLoopTop$
  tiraJmpCond "JLE", bufLen$, "0", numLoopDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + bufPtr$

  tiraJmpCond "JL", byteVal$, "48", numLoopDone$
  tiraJmpCond "JG", byteVal$, "57", numLoopDone$

  tiraOp TC_SUB, byteVal$, byteVal$, "48"
  tiraOp TC_MUL, resVar$, resVar$, "10"
  tiraOp TC_ADD, resVar$, resVar$, byteVal$

  tiraOp TC_ADD, bufPtr$, bufPtr$, "1"
  tiraOp TC_SUB, bufLen$, bufLen$, "1"
  tiraJmp numLoopTop$

  tiraLabel numLoopDone$

  applySignDone$ = tiraLabelCreateNew$("READ_SGN_APP")
  tiraJmpCond "JE", isNeg$, "0", applySignDone$
  tiraOp TC_NEG, resVar$, resVar$, ""
  tiraLabel applySignDone$

  lblSingle$ = tiraLabelCreateNew$("READ_IS_SNG")
  lblDouble$ = tiraLabelCreateNew$("READ_IS_DBL")
  lblByte$ = tiraLabelCreateNew$("READ_IS_BYT")
  lblInt$ = tiraLabelCreateNew$("READ_IS_INT")
  lblLong$ = tiraLabelCreateNew$("READ_IS_LNG")
  lblWriteDone$ = tiraLabelCreateNew$("READ_WR_DONE")

  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_SINGLE)), lblSingle$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_DOUBLE)), lblDouble$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_BYTE)), lblByte$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_UBYTE)), lblByte$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_INTEGER)), lblInt$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_UINTEGER)), lblInt$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_LONG)), lblLong$
  tiraJmpCond "JE", tgtDataTypeVar$, LTRIM$(STR$(TYPE_ULONG)), lblLong$

  tiraWriteMem targetAddrVar$, resVar$, "8"
  tiraJmp lblWriteDone$

  tiraLabel lblSingle$
  tiraWriteMem targetAddrVar$, resVar$, "SINGLE"
  tiraJmp lblWriteDone$

  tiraLabel lblDouble$
  tiraWriteMem targetAddrVar$, resVar$, "DOUBLE"
  tiraJmp lblWriteDone$

  tiraLabel lblByte$
  tiraWriteMem targetAddrVar$, resVar$, "1"
  tiraJmp lblWriteDone$

  tiraLabel lblInt$
  tiraWriteMem targetAddrVar$, resVar$, "2"
  tiraJmp lblWriteDone$

  tiraLabel lblLong$
  tiraWriteMem targetAddrVar$, resVar$, "4"

  tiraLabel lblWriteDone$

  tiraLabel endReadLbl$

  tiraRT_Epilogue

  tira_EndAndProcess

END SUB ' emitRuntimeRead

''''''''''''''''''''''''
SUB emitRuntimeStrAssign

  '''' String Assignment Runtime Helper
  ' Inputs: Arg1 = LHS Descriptor Ptr, Arg2 = RHS Descriptor Ptr
  rtOffset(RT_STR_ASSIGN) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"

  arg2Var$ = tiraDimVar$("ARG2", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg2Var$ + ", 2"

  fastRetLbl$ = tiraLabelCreateNew$("STR_FASTRET")
  skipFreeLbl$ = tiraLabelCreateNew$("STR_SKIPFREE")
  epilogueLbl$ = tiraLabelCreateNew$("STR_EPI")

  ' Check if LHS == RHS (e.g. A$ = A$) to prevent freeing the data we are trying to copy
  tiraJmpCond "JE", arg1Var$, arg2Var$, fastRetLbl$

  ' Check if LHS needs freeing (Flags == 1)
  lhsFlags$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, lhsFlags$ + ", " + arg1Var$ + ", 16"

  tiraJmpCond "JNE", lhsFlags$, "1", skipFreeLbl$

  ' Check if LHS Data Pointer is null
  lhsData$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, lhsData$ + ", " + arg1Var$

  tiraJmpCond "JE", lhsData$, "0", skipFreeLbl$

  ' Call HeapFree(hHeap, 0, dataPtr)
  tiraCall "IAT_HEAPFREE", 3, "!G_MEM_PROCESS_HEAP_PTR, 0, " + lhsData$

  tiraLabel skipFreeLbl$

  ' Get RHS length and data pointer
  rhsLen$ = tiraGetStringLen$(arg2Var$)
  rhsData$ = tiraGetStringData$(arg2Var$)

  doAllocLbl$ = tiraLabelCreateNew$("STR_DOALLOC")
  tiraJmpCond "JG", rhsLen$, "0", doAllocLbl$

  ' If length is 0, zero LHS Descriptor and exit early
  tiraBuildStringDescriptor arg1Var$, "0", "0", "0"

  tiraJmp epilogueLbl$

  tiraLabel doAllocLbl$

  ' Call HeapAlloc(hHeap, 0, length + 1)
  allocSize$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, allocSize$, rhsLen$, "1"

  tiraCall "IAT_HEAPALLOC", 3, "!G_MEM_PROCESS_HEAP_PTR, 0, " + allocSize$

  newPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RET, newPtr$

  ' Update LHS Desc with the newly allocated memory address
  tiraBuildStringDescriptor arg1Var$, newPtr$, rhsLen$, "1"

  ' Copy Data
  tiraMemcpy newPtr$, rhsData$, rhsLen$

  ' Write null terminator at the end of the newly copied string data
  nullPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, nullPtr$, newPtr$, rhsLen$
  tiraWriteMem nullPtr$, "0", "1"

  tiraLabel epilogueLbl$
  tiraLabel fastRetLbl$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeStrAssign

''''''''''''''''''''''''
SUB emitRuntimeStrCmp

  rtOffset(RT_STR_CMP) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"
  arg2Var$ = tiraDimVar$("ARG2", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg2Var$ + ", 2"

  ' Extract LHS Data and Length
  lhsData$ = tiraGetStringData$(arg1Var$)
  lhsLen$ = tiraGetStringLen$(arg1Var$)

  ' Extract RHS Data and Length
  rhsData$ = tiraGetStringData$(arg2Var$)
  rhsLen$ = tiraGetStringLen$(arg2Var$)

  ' Find Min Length to ensure safe memory scanning
  minLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign minLen$, lhsLen$

  skipMinLbl$ = tiraLabelCreateNew$("STRCMP_MIN")
  tiraJmpCond "JLE", lhsLen$, rhsLen$, skipMinLbl$
  tiraAssign minLen$, rhsLen$
  tiraLabel skipMinLbl$

  ' Setup Comparison Loop
  idx$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign idx$, "0"

  loopTop$ = tiraLabelCreateNew$("STRCMP_LOOP")
  loopDone$ = tiraLabelCreateNew$("STRCMP_DONE")

  tiraLabel loopTop$
  tiraJmpCond "JGE", idx$, minLen$, loopDone$

  ' Read LHS Byte
  lhsCharAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, lhsCharAddr$, lhsData$, idx$
  lhsByte$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, lhsByte$ + ", " + lhsCharAddr$

  ' Read RHS Byte
  rhsCharAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, rhsCharAddr$, rhsData$, idx$
  rhsByte$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, rhsByte$ + ", " + rhsCharAddr$

  ' Compare Bytes
  charLessLbl$ = tiraLabelCreateNew$("STRCMP_CLESS")
  charGrtrLbl$ = tiraLabelCreateNew$("STRCMP_CGRTR")

  tiraJmpCond "JL", lhsByte$, rhsByte$, charLessLbl$
  tiraJmpCond "JG", lhsByte$, rhsByte$, charGrtrLbl$

  ' Bytes match, increment index and evaluate next character
  tiraOp TC_ADD, idx$, idx$, "1"
  tiraJmp loopTop$

  tiraLabel loopDone$

  ' If we reached here, the strings match flawlessly up to minLen. Compare overall lengths
  lenLessLbl$ = tiraLabelCreateNew$("STRCMP_LLESS")
  lenGrtrLbl$ = tiraLabelCreateNew$("STRCMP_LGRTR")
  endLbl$ = tiraLabelCreateNew$("STRCMP_END")

  tiraJmpCond "JL", lhsLen$, rhsLen$, lenLessLbl$
  tiraJmpCond "JG", lhsLen$, rhsLen$, lenGrtrLbl$

  ' Lengths are equal. The string matches exactly.
  tiraAssign arg1Var$, "0"
  tiraJmp endLbl$

  ' LHS < RHS
  tiraLabel lenLessLbl$
  tiraLabel charLessLbl$
  tiraAssign arg1Var$, "-1"
  tiraJmp endLbl$

  ' LHS > RHS
  tiraLabel lenGrtrLbl$
  tiraLabel charGrtrLbl$
  tiraAssign arg1Var$, "1"

  tiraLabel endLbl$

  ' Cleanly pass the evaluated return value back to the caller frame
  tiraNew TC_ABI_WRITE_RET, arg1Var$
  tiraRT_Epilogue

  tira_EndAndProcess

END SUB ' emitRuntimeStrCmp

''''''''''''''''''''''''
SUB emitRuntimeSwapBuffers

  rtOffset(RT_SWAP_BUFFERS) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  ' Acquire Spinlock safely using hardware XCHG
  lblSpin$ = tiraLabelCreateNew$("SWAP_SPIN")
  lblAcq$ = tiraLabelCreateNew$("SWAP_ACQ")
  tiraLabel lblSpin$
  spinVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign spinVal$, "1"
  tiraNew TC_XCHG, "!G_WND_RENDER_LOCK_FLAG, " + spinVal$ + ", 4"
  tiraJmpCond "JE", spinVal$, "0", lblAcq$
  tiraCall "IAT_SLEEP", 1, "0"
  tiraJmp lblSpin$
  tiraLabel lblAcq$

  ' Swap Pointers
  tmpPtr$ = tiraDimVar$("T", TYPE_INTEGER64)

  tiraAssign tmpPtr$, "!G_FRAMEBUF_FRONT_PTR"
  tiraAssign "!G_FRAMEBUF_FRONT_PTR", "!G_FRAMEBUF_BACK_PTR"
  tiraAssign "!G_FRAMEBUF_BACK_PTR", tmpPtr$

  tiraAssign tmpPtr$, "!G_GFX_BUF_FRONT_PTR"
  tiraAssign "!G_GFX_BUF_FRONT_PTR", "!G_GFX_BUF_BACK_PTR"
  tiraAssign "!G_GFX_BUF_BACK_PTR", tmpPtr$

  ' Synchronize snapshot counts
  tiraAssign "!G_GFX_BUF_COUNT_FRONT_VAL", "!G_GFX_BUF_COUNT_BACK_VAL"

  ' Release Spinlock
  tiraAssign "!G_WND_RENDER_LOCK_FLAG", "0"

  ' Instruct Windows to repaint the window using the newly swapped Front buffer
  tiraCall "IAT_INVALIDATERECT", 3, "!G_LAYOUT_HWND_VAL, 0, 0"

  ' Copy the new Front Buffer memory into the new Back Buffer memory to preserve
  ' persistence so the user thread continues drawing on top of existing graphics
  fbSize$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign fbSize$, LTRIM$(STR$(gfxConfig.SizeX * gfxConfig.SizeY))
  tiraMemcpy "!G_FRAMEBUF_BACK_PTR", "!G_FRAMEBUF_FRONT_PTR", fbSize$

  txtSize$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign txtSize$, LTRIM$(STR$(4096 * layout.GfxBufEntrySize))
  tiraMemcpy "!G_GFX_BUF_BACK_PTR", "!G_GFX_BUF_FRONT_PTR", txtSize$

  tiraRT_Epilogue
  tira_EndAndProcess

END SUB ' emitRuntimeSwapBuffers

''''''''''''''''''''''''
SUB emitRuntimeVehHandler

  '''' RT_VEH_HANDLER
  rtOffset(RT_VEH_HANDLER) = stream.emitPos

  tira_Start
  tiraRT_Prologue

  arg1Var$ = tiraDimVar$("ARG1", TYPE_INTEGER64)
  tiraNew TC_ABI_READ_ARG, arg1Var$ + ", 1"

  excPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign excPtr$, arg1Var$

  ' Read ExceptionRecord pointer (offset 0)
  excRecPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, excRecPtr$ + ", " + excPtr$

  ' Read ExceptionCode from the ExceptionRecord structure
  excCode$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, excCode$ + ", " + excRecPtr$

  lblMatch$ = tiraLabelCreateNew$("VEH_MATCH")
  lblEnd$ = tiraLabelCreateNew$("VEH_END")

  ' Check for integer divide by zero (0xC0000094 -> -1073741676)
  tiraJmpCond "JE", excCode$, "-1073741676", lblMatch$

  ' Check for float divide by zero (0xC000008E -> -1073741682)
  tiraJmpCond "JE", excCode$, "-1073741682", lblMatch$

  ' Not a recognized exception, gracefully pass it back to Windows returning EXCEPTION_CONTINUE_SEARCH (0) in RAX
  tiraAssign arg1Var$, "0"
  tiraJmp lblEnd$

  tiraLabel lblMatch$

  ' Determine the target RIP
  targetRip$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign targetRip$, "!G_SYS_ERR_HANDLER_PTR"

  lblHasHandler$ = tiraLabelCreateNew$("VEH_HAS_HDL")
  tiraJmpCond "JNE", targetRip$, "0", lblHasHandler$

  ' No user handler, use native
  tiraOp TC_ADDRESS_OF, targetRip$, "@NATIVE_DIV_ZERO_HANDLER", ""

  tiraLabel lblHasHandler$

  ' Start modifying the CPU CONTEXT struct to safely route execution into our basic program space by reading ContextRecord pointer (offset 8)
  ctxPtrAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, ctxPtrAddr$, excPtr$, "8"

  ctxPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, ctxPtr$ + ", " + ctxPtrAddr$

  ' Navigate to Context.Rsp to reset the dirty execution stack (offset 152)
  rspPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, rspPtr$, ctxPtr$, "152"
  tiraWriteMem rspPtr$, "!G_SYS_SAFE_RSP_PTR", "8"

  ' Write it into Context.Rbp to pull the base pointer out of any deep subroutine frames (offset 160)
  rbpPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, rbpPtr$, ctxPtr$, "160"
  tiraWriteMem rbpPtr$, "!G_SYS_SAFE_RSP_PTR", "8"

  ' Redirect the instruction pointer (offset 248)
  ripPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, ripPtr$, ctxPtr$, "248"

  ' Save the crashing instruction address for the RESUME keyword
  crashRip$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, crashRip$ + ", " + ripPtr$
  tiraAssign "!G_SYS_LAST_ERR_PTR", crashRip$

  ' Write the target address into Context.Rip
  tiraWriteMem ripPtr$, targetRip$, "8"

  ' Return EXCEPTION_CONTINUE_EXECUTION (-1) so Windows allows the thread to seamlessly continue
  tiraAssign arg1Var$, "-1"

  tiraLabel lblEnd$

  tiraNew TC_ABI_WRITE_RET, arg1Var$
  tiraRT_Epilogue

  '''' Append the native error handler to the compiled output space immediately following the VEH handler

  tiraLabel "@NATIVE_DIV_ZERO_HANDLER"
  tiraCall "RT_PRINT_STR", 1, CHR$(34) + "UNHANDLED DIVISION BY ZERO, PROGRAM END" + CHR$(34)
  tiraCall "RT_CRLF", 0, ""
  tiraJmp "@END_PROGRAM"

  tiraLabel "@NATIVE_BOUNDS_HANDLER"
  tiraCall "RT_PRINT_STR", 1, CHR$(34) + "ARRAY OUT OF BOUNDS, PROGRAM END" + CHR$(34)
  tiraCall "RT_CRLF", 0, ""
  tiraJmp "@END_PROGRAM"

  tira_EndAndProcess

END SUB ' emitRuntimeVehHandler

''''''''''''''''''''''''
FUNCTION evalMathConst$ (wExpr$)

  DIM pStart AS LONG
  DIM pEnd AS LONG
  DIM eLen AS LONG
  DIM evalStr$
  DIM resStr$

  DIM tTokens$(64)
  DIM tCount AS LONG

  DIM nTokens$(64)
  DIM nCount AS LONG
  DIM iToken AS LONG

  IF LEFT$(wExpr$, 1) = CHR$(34) THEN
    evalMathConst$ = wExpr$
    EXIT FUNCTION
  END IF

  DO
    pEnd = INSTR(wExpr$, ")")
    IF pEnd > 0 THEN
      pStart = 0
      FOR ix = pEnd - 1 TO 1 STEP -1
        IF MID$(wExpr$, ix, 1) = "(" THEN
          pStart = ix
          EXIT FOR
        END IF
      NEXT

      IF pStart > 0 THEN
        evalStr$ = MID$(wExpr$, pStart + 1, pEnd - pStart - 1)
      ELSE
        ' Mismatched parenthesis safety fallback
        evalMathConst$ = wExpr$
        EXIT FUNCTION
      END IF
    ELSE
      evalStr$ = wExpr$
    END IF

    tCount = 0
    eLen = LEN(evalStr$)
    ix = 1

    DO WHILE ix <= eLen
      ch$ = MID$(evalStr$, ix, 1)
      IF ch$ = " " OR ch$ = CHR$(9) THEN
        ix = ix + 1
      ELSE
        IF ch$ = "+" OR ch$ = "-" OR ch$ = "*" OR ch$ = "/" OR ch$ = "\" THEN
          tTokens$(tCount) = ch$
          tCount = tCount + 1
          ix = ix + 1
        ELSE
          uCh$ = UCASE$(ch$)
          IF (uCh$ >= "A" AND uCh$ <= "Z") THEN
            wordStr$ = ""
            DO WHILE ix <= eLen
              c2$ = MID$(evalStr$, ix, 1)
              u2$ = UCASE$(c2$)
              IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") THEN
                wordStr$ = wordStr$ + c2$
                ix = ix + 1
              ELSE
                EXIT DO
              END IF
            LOOP
            tTokens$(tCount) = wordStr$
            tCount = tCount + 1
          ELSE
            num$ = ""
            DO WHILE ix <= eLen
              c2$ = MID$(evalStr$, ix, 1)
              IF (c2$ >= "0" AND c2$ <= "9") OR c2$ = "." THEN
                num$ = num$ + c2$
                ix = ix + 1
              ELSE
                IF c2$ = "&" AND num$ = "" AND ix < eLen THEN
                  IF UCASE$(MID$(evalStr$, ix + 1, 1)) = "H" THEN
                    num$ = "&H"
                    ix = ix + 2
                    DO WHILE ix <= eLen
                      c3$ = UCASE$(MID$(evalStr$, ix, 1))
                      IF (c3$ >= "0" AND c3$ <= "9") OR (c3$ >= "A" AND c3$ <= "F") THEN
                        num$ = num$ + c3$
                        ix = ix + 1
                      ELSE
                        EXIT DO
                      END IF
                    LOOP
                  ELSE
                    EXIT DO
                  END IF
                ELSE
                  EXIT DO
                END IF
              END IF
            LOOP
            IF num$ <> "" THEN
              tTokens$(tCount) = num$
              tCount = tCount + 1
            ELSE
              tTokens$(tCount) = MID$(evalStr$, ix, 1)
              tCount = tCount + 1
              ix = ix + 1
            END IF
          END IF
        END IF
      END IF
    LOOP

    IF tCount = 0 THEN
      resStr$ = ""
    ELSE
      ' Pass 1A: Unary minus
      nCount = 0
      iToken = 0
      DO WHILE iToken < tCount
        IF tTokens$(iToken) = "-" THEN
          isUnary = 0
          IF iToken = 0 THEN isUnary = 1
          IF iToken > 0 THEN
            prev$ = UCASE$(tTokens$(iToken - 1))
            IF prev$ = "+" OR prev$ = "-" OR prev$ = "*" OR prev$ = "/" OR prev$ = "\" OR prev$ = "NOT" THEN isUnary = 1
          END IF
          IF isUnary = 1 AND iToken + 1 < tCount THEN
            nTokens$(nCount) = "-" + tTokens$(iToken + 1)
            nCount = nCount + 1
            iToken = iToken + 2
          ELSE
            nTokens$(nCount) = tTokens$(iToken)
            nCount = nCount + 1
            iToken = iToken + 1
          END IF
        ELSE
          nTokens$(nCount) = tTokens$(iToken)
          nCount = nCount + 1
          iToken = iToken + 1
        END IF
      LOOP

      FOR ii = 0 TO nCount - 1
        tTokens$(ii) = nTokens$(ii)
      NEXT
      tCount = nCount

      ' Pass 1B: Unary NOT
      nCount = 0
      iToken = 0
      DO WHILE iToken < tCount
        IF UCASE$(tTokens$(iToken)) = "NOT" THEN
          IF iToken + 1 < tCount THEN
            valRes = NOT VAL(tTokens$(iToken + 1))
            nTokens$(nCount) = LTRIM$(RTRIM$(STR$(valRes)))
            nCount = nCount + 1
            iToken = iToken + 2
          ELSE
            nTokens$(nCount) = tTokens$(iToken)
            nCount = nCount + 1
            iToken = iToken + 1
          END IF
        ELSE
          nTokens$(nCount) = tTokens$(iToken)
          nCount = nCount + 1
          iToken = iToken + 1
        END IF
      LOOP

      FOR ii = 0 TO nCount - 1
        tTokens$(ii) = nTokens$(ii)
      NEXT
      tCount = nCount

      ' Pass 2: Multiplication and Division
      nCount = 0
      iToken = 0
      DO WHILE iToken < tCount
        IF tTokens$(iToken) = "*" OR tTokens$(iToken) = "/" OR tTokens$(iToken) = "\" THEN
          IF nCount > 0 AND iToken + 1 < tCount THEN
            val1 = VAL(nTokens$(nCount - 1))
            val2 = VAL(tTokens$(iToken + 1))
            IF tTokens$(iToken) = "*" THEN res = val1 * val2
            IF tTokens$(iToken) = "/" THEN
              IF val2 <> 0 THEN res = val1 / val2 ELSE res = 0
            END IF
            IF tTokens$(iToken) = "\" THEN
              IF val2 <> 0 THEN res = val1 \ val2 ELSE res = 0
            END IF
            nTokens$(nCount - 1) = LTRIM$(RTRIM$(STR$(res)))
            iToken = iToken + 2
          ELSE
            nTokens$(nCount) = tTokens$(iToken)
            nCount = nCount + 1
            iToken = iToken + 1
          END IF
        ELSE
          nTokens$(nCount) = tTokens$(iToken)
          nCount = nCount + 1
          iToken = iToken + 1
        END IF
      LOOP

      FOR ii = 0 TO nCount - 1
        tTokens$(ii) = nTokens$(ii)
      NEXT
      tCount = nCount

      ' Pass 3: Addition and Subtraction
      nCount = 0
      iToken = 0
      DO WHILE iToken < tCount
        IF tTokens$(iToken) = "+" OR tTokens$(iToken) = "-" THEN
          IF nCount > 0 AND iToken + 1 < tCount THEN
            val1 = VAL(nTokens$(nCount - 1))
            val2 = VAL(tTokens$(iToken + 1))
            IF tTokens$(iToken) = "+" THEN res = val1 + val2
            IF tTokens$(iToken) = "-" THEN res = val1 - val2
            nTokens$(nCount - 1) = LTRIM$(RTRIM$(STR$(res)))
            iToken = iToken + 2
          ELSE
            nTokens$(nCount) = tTokens$(iToken)
            nCount = nCount + 1
            iToken = iToken + 1
          END IF
        ELSE
          nTokens$(nCount) = tTokens$(iToken)
          nCount = nCount + 1
          iToken = iToken + 1
        END IF
      LOOP

      resStr$ = nTokens$(0)
    END IF

    IF pEnd > 0 THEN
      wExpr$ = LEFT$(wExpr$, pStart - 1) + resStr$ + MID$(wExpr$, pEnd + 1)
    ELSE
      evalMathConst$ = resStr$
      EXIT FUNCTION
    END IF
  LOOP

END FUNCTION ' evalMathConst$

''''''''''''''''''''''''
FUNCTION extractQuotes$ (wStr$)

  tempReturn$ = ""
  firstQuote = INSTR(wStr$, CHR$(34))

  IF firstQuote > 0 THEN
    secondQuote = INSTR(firstQuote + 1, wStr$, CHR$(34))
    IF secondQuote > 0 THEN
      tempReturn$ = MID$(wStr$, firstQuote + 1, secondQuote - firstQuote - 1)
    END IF
  END IF

  extractQuotes$ = tempReturn$

END FUNCTION ' extractQuotes$

''''''''''''''''''''''''
SUB fileBitmapLoad

  fln$ = fileNameBMP$

  IF _FILEEXISTS(fln$) = 0 THEN EXIT SUB

  rwvar$ = " " ' Necessary, or QB64 won't read correctly
  OPEN fln$ FOR BINARY AS #1

  IF LOF(1) = 0 THEN
    CLOSE #1
    KILL fln$
    EXIT SUB
  END IF

  ' Skip the 54-byte BMP header
  FOR ii = 1 TO 54
    GET #1, , rwvar$
  NEXT

  ' Read the 256-color palette
  palCounter = 0
  FOR ii = 0 TO 255
    GET #1, , rwvar$
    wVal = ASC(rwvar$)
    bmpPal256(palCounter, palBLUE) = wVal

    GET #1, , rwvar$
    wVal = ASC(rwvar$)
    bmpPal256(palCounter, palGREEN) = wVal

    GET #1, , rwvar$
    wVal = ASC(rwvar$)
    bmpPal256(palCounter, palRED) = wVal

    GET #1, , rwvar$
    palCounter = palCounter + 1
  NEXT

  CLOSE #1

  editor.windowBarClr = 208 ' Dark blue for window if the bitmap file exists
  editor.CloseClr = 32

  editor.HasCustomPalette = 1

END SUB ' fileBitmapLoad

''''''''''''''''''''''''
SUB fileCodeLoad

  fln$ = fileNameCode$

  IF _FILEEXISTS(fln$) = 0 THEN EXIT SUB

  rwVar$ = " " ' Necessary, or QB64 won't read correctly
  OPEN fln$ FOR BINARY AS #1

  IF LOF(1) = 0 THEN
    CLOSE #1
    KILL fln$
    EXIT SUB
  END IF

  FOR iy = 1 TO EDITOR_LINE_MAX
    editorText$(iy) = ""
  NEXT

  curY = 1
  FOR ii = 1 TO LOF(1)
    GET #1, , rwVar$
    IF rwVar$ = CHR$(13) THEN
      ' Ignore carriage return
    ELSE
      IF rwVar$ = CHR$(10) THEN
        curY = curY + 1
        IF curY > EDITOR_LINE_MAX THEN EXIT FOR
      ELSE
        IF curY <= EDITOR_LINE_MAX THEN
          editorText$(curY) = editorText$(curY) + rwVar$
        END IF
      END IF
    END IF
  NEXT

  CLOSE #1

  editor.LastLine = curY
  IF editor.LastLine > EDITOR_LINE_MAX THEN editor.LastLine = EDITOR_LINE_MAX

  IF editor.CursorY > editor.LastLine THEN
    editor.CursorY = editor.LastLine
    editor.CursorX = 0
  END IF

  IF editor.ScrollY > editor.LastLine THEN
    editor.ScrollY = editor.LastLine - 27
    IF editor.ScrollY < 1 THEN editor.ScrollY = 1
  END IF

END SUB ' fileCodeLoad

''''''''''''''''''''''''
SUB fileCodeSave

  ' Unlike the load function, this function uses the faster method

  rwVar$ = " " ' Necessary, or QB64 won't work correctly

  fln$ = fileNameCode$

  OPEN fln$ FOR BINARY AS #1
  IF LOF(1) > 0 THEN
    CLOSE #1
    KILL fln$
    OPEN fln$ FOR BINARY AS #1
  END IF

  lastLine = editor.LastLine
  newline$ = CHR$(10)

  FOR iy = 1 TO lastLine
    IF iy > 1 THEN
      PUT #1, , newline$
    END IF
    rwVar$ = editorText$(iy)
    PUT #1, , rwVar$
  NEXT

  CLOSE #1

END SUB ' fileCodeSave

''''''''''''''''''''''''
SUB fileMenuOpenModal

  DIM fileList$(1000)
  DIM fileCount AS LONG
  DIM localScrollY AS LONG
  DIM localDragActive AS LONG
  DIM localDragOffset AS LONG

  ' Get directory listing safely
  SHELL _HIDE "cmd /c dir /b /a-d *.bas > flist.tmp"

  fileCount = 0
  IF _FILEEXISTS("flist.tmp") THEN
    ffTmp = FREEFILE
    OPEN "flist.tmp" FOR INPUT AS #ffTmp
    DO WHILE NOT EOF(ffTmp) AND fileCount < 1000
      LINE INPUT #ffTmp, fileLine$
      fileLine$ = LTRIM$(RTRIM$(fileLine$))
      IF fileLine$ <> "" AND UCASE$(fileLine$) <> "FLIST.TMP" THEN
        fileList$(fileCount) = fileLine$
        fileCount = fileCount + 1
      END IF
    LOOP
    CLOSE #ffTmp
    KILL "flist.tmp"
  END IF

  IF fileCount = 0 THEN
    addStatusMsg "NO BAS FILES FOUND"
    EXIT SUB
  END IF

  localScrollY = 0
  localDragActive = 0
  localDragOffset = 0

  ' Ensure clean key state
  _KEYCLEAR

  DO
    limitSpeed
    mouseReadInput

    redrawAll

    boxW = 200
    boxH = 240
    boxX = (SCREENSIZEX - boxW) \ 2
    boxY = (SCREENSIZEY - boxH) \ 2

    drawBorderBox boxX, boxY, boxW, boxH, 15, editor.windowBarClr

    closeBtnW = 15
    closeBtnH = 13
    closeBtnX = boxX + boxW - closeBtnW
    closeBtnY = boxY
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, 0, 1

    IF mouseClickedInBox(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
      EXIT DO
    END IF

    PrintStr boxX + (boxW \ 2) - (9 * 4), boxY + 3, "OPEN FILE", 14, 0, 1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    itemH = 10
    maxLines = (boxH - 15) \ itemH

    ' Scrollbar
    scrollBarX = boxX + boxW - 12
    scrollBarY = boxY + 14
    scrollBarW = 12
    scrollBarH = boxH - 15

    localScrollY = processVScrollbar(scrollBarX, scrollBarY, scrollBarW, scrollBarH, fileCount, maxLines, localScrollY, localDragActive, localDragOffset, 0)
    localDragActive = returnedData2
    localDragOffset = returnedData3

    ' Mouse wheel
    IF mouse.Wheel <> 0 THEN
      IF mouseWithinBoxBounds(boxX, boxY, boxW, boxH) THEN
        localScrollY = localScrollY + mouse.Wheel
        maxScroll = fileCount - maxLines
        IF maxScroll < 0 THEN maxScroll = 0
        IF localScrollY > maxScroll THEN localScrollY = maxScroll
        IF localScrollY < 0 THEN localScrollY = 0
      END IF
    END IF

    ' Draw items
    FOR ii = 0 TO maxLines - 1
      fIdx = ii + localScrollY
      IF fIdx < fileCount THEN
        itemY = boxY + 14 + (ii * itemH)
        sOutName$ = fileList$(fIdx)
        IF LEN(sOutName$) > 20 THEN sOutName$ = LEFT$(sOutName$, 20)

        ' Hover
        IF mouseWithinBoxBounds(boxX + 2, itemY, boxW - 16, itemH) THEN
          drawClearBox boxX + 2, itemY, boxW - 16, itemH, 9

          IF mouseClickedInBox(boxX + 2, itemY, boxW - 16, itemH) THEN
            LINE (boxX + 2, itemY)-(boxX + boxW - 15, itemY + itemH - 1), 1, BF
            PrintStr boxX + 8, itemY + 1, sOutName$, 15, 0, 1

            _DISPLAY
            waitTimer UI_FLASH_TIME

            fileNameCode$ = fileList$(fIdx)
            fileCodeLoad
            refineCode (0)

            editor.CursorY = 1
            editor.CursorX = 0
            editor.ScrollY = 1
            editor.ScrollX = 0
            editor.SelectStartX = 0
            editor.SelectStartY = 1
            editor.IsSelecting = 0
            editor.Focus = 1

            addStatusMsg "LOADED " + fileNameCode$

            EXIT DO
          END IF
        END IF

        PrintStr boxX + 8, itemY + 1, sOutName$, 11, 0, 1
      END IF
    NEXT

    _DISPLAY

    kVal = keyCheck("ESC")
    IF kVal = 27 THEN
      waitKeyRelease "ESC"
      EXIT DO
    END IF

  LOOP

END SUB ' fileMenuOpenModal

''''''''''''''''''''''''
SUB fileMenuSaveModal

  saveAsName$ = fileNameCode$

  _KEYCLEAR

  DO
    limitSpeed
    mouseReadInput

    redrawAll

    boxW = 320
    boxH = 64
    boxX = (SCREENSIZEX - boxW) \ 2
    boxY = (SCREENSIZEY - boxH) \ 2

    drawBorderBox boxX, boxY, boxW, boxH, 15, editor.windowBarClr
    PrintStr boxX + (boxW \ 2) - 28, boxY + 3, "SAVE AS", 14, 0, 1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    closeBtnW = 15
    closeBtnH = 13
    closeBtnX = boxX + boxW - closeBtnW
    closeBtnY = boxY
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, 0, 1

    IF mouseClickedInBox(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
      EXIT DO
    END IF

    ' Input box
    inputBoxX = boxX + 16
    inputBoxY = boxY + 24
    inputBoxW = boxW - 32
    inputBoxH = 16
    drawBorderBox inputBoxX, inputBoxY, inputBoxW, inputBoxH, 15, 0

    ' Draw text
    PrintStr inputBoxX + 4, inputBoxY + 4, saveAsName$ + "_", 15, 0, 1

    _DISPLAY

    kVal = _KEYHIT
    IF kVal <> 0 THEN
      IF kVal = 27 THEN ' ESC
        waitKeyRelease "ESC"
        EXIT DO
      END IF

      IF kVal = 13 THEN ' ENTER
        IF saveAsName$ <> "" THEN
          fileNameCode$ = saveAsName$
          fileCodeSave
          addStatusMsg "SAVED AS " + fileNameCode$
        END IF
        EXIT DO
      END IF

      IF kVal = 8 THEN ' Backspace
        qLen = LEN(saveAsName$)
        IF qLen > 0 THEN
          saveAsName$ = LEFT$(saveAsName$, qLen - 1)
        END IF
      ELSE
        IF kVal >= 32 AND kVal <= 126 THEN
          IF LEN(saveAsName$) < 34 THEN
            saveAsName$ = saveAsName$ + CHR$(kVal)
          END IF
        END IF
      END IF
    END IF

  LOOP

END SUB ' fileMenuSaveModal

''''''''''''''''''''''''
SUB fileOutputErrorReport (wStr1$, wStr2$)

  rwVar$ = " " ' Necessary, or QB64 won't work correctly

  fln$ = fileNameErr$

  OPEN fln$ FOR BINARY AS #1
  IF LOF(1) > 0 THEN
    CLOSE #1
    KILL fln$
    OPEN fln$ FOR BINARY AS #1
  END IF

  FOR ix = 1 TO LEN(wStr1$)
    rwVar$ = MID$(wStr1$, ix, 1)
    PUT #1, , rwVar$
  NEXT

  rwVar$ = CHR$(13)
  PUT #1, , rwVar$
  rwVar$ = CHR$(10)
  PUT #1, , rwVar$

  IF wStr2$ <> "" THEN
    FOR ix = 1 TO LEN(wStr2$)
      rwVar$ = MID$(wStr2$, ix, 1)
      PUT #1, , rwVar$
    NEXT
    rwVar$ = CHR$(13)
    PUT #1, , rwVar$
    rwVar$ = CHR$(10)
    PUT #1, , rwVar$
  END IF

  CLOSE #1

END SUB ' fileOutputErrorReport

''''''''''''''''''''''''
SUB fileSaveBinary

  fln$ = fileNameOut$

  ' Attempt to silently delete the file via OS shell before QB64 tries to OPEN it
  IF _FILEEXISTS(fln$) THEN
    delCmd$ = "cmd /c del /F /Q " + CHR$(34) + fln$ + CHR$(34)
    SHELL _HIDE delCmd$

    waitTimer 0.1

    ' If the file still exists, it is locked by a running process
    IF _FILEEXISTS(fln$) THEN
      addStatusMsg "ERROR: OUTPUT FILE IN USE"
      EXIT SUB
    END IF
  END IF

  OPEN fln$ FOR BINARY AS #1
  IF LOF(1) > 0 THEN
    CLOSE #1
    KILL fln$
    OPEN fln$ FOR BINARY AS #1
  END IF

  IF outputFileIdx > 0 THEN
    outStr$ = SPACE$(outputFileIdx)
    FOR ii = 0 TO outputFileIdx - 1
      ASC(outStr$, ii + 1) = outputFile(ii)
    NEXT
    PUT #1, , outStr$
  END IF

  CLOSE #1

END SUB ' fileSaveBinary

''''''''''''''''''''''''
FUNCTION findComma (startIdx, endIdx)

  DIM commaPos AS LONG

  commaPos = 0
  ff = findNextTokenAtDepth0(startIdx, endIdx, 256 + ASC(","))
  IF ff = 1 THEN
    commaPos = returnedData2
  END IF

  findComma = commaPos

END FUNCTION ' findComma

''''''''''''''''''''''''
SUB findEditorNext

  ' When a match is found, it performs the following tasks:
  ' Updates the cursor position (editor.CursorX and editor.CursorY).
  ' Sets the selection boundaries to highlight the found text.
  ' Adjusts the horizontal and vertical scroll offsets so the found text is visible on the screen.
  ' Assigns focus to the editor window.

  IF editorSearchQuery$ = "" THEN EXIT SUB

  foundMatch = 0
  uQuery$ = UCASE$(editorSearchQuery$)

  FOR iy = editor.CursorY TO editor.LastLine
    uLine$ = UCASE$(editorText$(iy))
    matchPos = INSTR(uLine$, uQuery$)

    IF matchPos > 0 AND iy = editor.CursorY THEN
      matchPos = INSTR(editor.CursorX + 2, uLine$, uQuery$)
    END IF

    IF matchPos > 0 THEN
      editor.CursorY = iy
      editor.CursorX = matchPos - 1
      editor.SelectStartY = iy
      editor.SelectStartX = matchPos - 1 + LEN(uQuery$)
      editor.IsSelecting = 1
      editor.Focus = 1

      editor.ScrollY = editor.CursorY - 14
      IF editor.ScrollY < 1 THEN editor.ScrollY = 1
      editor.ScrollX = editor.CursorX - 20
      IF editor.ScrollX < 0 THEN editor.ScrollX = 0

      foundMatch = 1
      EXIT FOR
    END IF
  NEXT

  IF foundMatch = 0 THEN
    FOR iy = 1 TO editor.CursorY
      uLine$ = UCASE$(editorText$(iy))
      matchPos = INSTR(uLine$, uQuery$)

      IF matchPos > 0 THEN
        editor.CursorY = iy
        editor.CursorX = matchPos - 1
        editor.SelectStartY = iy
        editor.SelectStartX = matchPos - 1 + LEN(uQuery$)
        editor.IsSelecting = 1
        editor.Focus = 1

        editor.ScrollY = editor.CursorY - 14
        IF editor.ScrollY < 1 THEN editor.ScrollY = 1
        editor.ScrollX = editor.CursorX - 20
        IF editor.ScrollX < 0 THEN editor.ScrollX = 0

        addStatusMsg "SEARCH RESTARTED AT TOP"

        foundMatch = 1
        EXIT FOR
      END IF
    NEXT
  END IF

  IF foundMatch = 0 THEN
    addStatusMsg "SEARCH: NO MATCHES FOUND"
  END IF

END SUB ' findEditorNext

''''''''''''''''''''''''
FUNCTION findInstructionEnd (startIdx)

  returnExtraPrepare

  sPassEndInx = lineTokenCount - 1

  parenDepth = 0
  FOR ii = startIdx TO lineTokenCount - 1
    tVal = lineTokenVals(ii)
    IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
    IF tVal = 256 + ASC(")") THEN
      parenDepth = parenDepth - 1
      IF parenDepth < 0 THEN
        throwCompilerError "UNEXPECTED )", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF

    IF parenDepth = 0 THEN
      IF tVal = 256 + ASC(":") THEN
        sPassEndInx = ii - 1
        EXIT FOR
      END IF

      ' Prevent the tokenizer from swallowing chained statements like NEXT varName
      IF ii > startIdx THEN
        IF tVal = TOK_NEXT OR tVal = TOK_GOTO THEN
          sPassEndInx = ii - 1
          EXIT FOR
        END IF
      END IF
    END IF
  NEXT

  IF parenDepth > 0 THEN
    throwCompilerError "MISSING )", ASIS, 0
    EXIT FUNCTION
  END IF

  return2 sPassEndInx
  findInstructionEnd = 1

END FUNCTION ' findInstructionEnd

''''''''''''''''''''''''
FUNCTION findMatchingParen (startIdx, endIdx)

  returnExtraPrepare

  DIM pDepth AS LONG
  DIM tVal AS LONG

  pDepth = 0

  FOR ii = startIdx TO endIdx
    tVal = lineTokenVals(ii)
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN
      pDepth = pDepth - 1
      IF pDepth = 0 THEN
        return2 ii
        findMatchingParen = 1
        EXIT FUNCTION
      END IF
    END IF
  NEXT

END FUNCTION ' findMatchingParen

''''''''''''''''''''''''
FUNCTION findNextTokenAtDepth0 (startIdx, endIdx, passTokVal)

  returnExtraPrepare

  DIM pDepth AS LONG
  DIM tVal AS LONG

  pDepth = 0

  FOR ii = startIdx TO endIdx
    tVal = lineTokenVals(ii)
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND tVal = passTokVal THEN
      return2 ii
      findNextTokenAtDepth0 = 1
      EXIT FUNCTION
    END IF
  NEXT

END FUNCTION ' findNextTokenAtDepth0

''''''''''''''''''''''''
FUNCTION findSubIndex (passName$)

  ' Sub index 0 is reserved for the main program

  returnExtraPrepare

  searchName$ = RTRIM$(passName$)

  FOR ii = 1 TO subCount - 1
    IF RTRIM$(subs(ii).RecordName) = searchName$ THEN
      return2 ii
      findSubIndex = 1
      EXIT FUNCTION
    END IF
  NEXT

END FUNCTION ' findSubIndex

''''''''''''''''''''''''
FUNCTION findSubIndexByScope (passScopeID AS LONG)

  returnExtraPrepare

  FOR ii = 1 TO subCount - 1
    IF subs(ii).ScopeID = passScopeID THEN
      return2 ii
      findSubIndexByScope = 1
      EXIT FUNCTION
    END IF
  NEXT

END FUNCTION ' findSubIndexByScope

''''''''''''''''''''''''
FUNCTION findSymbol (vName$)

  returnExtraPrepare

  DIM hVal AS LONG
  DIM checkIdx AS LONG
  DIM globalIdx AS LONG
  DIM firstCh AS STRING * 1

  searchName$ = UCASE$(vName$)
  globalIdx = -1
  hVal = hashString(searchName$)
  checkIdx = symHash(hVal)
  firstCh = LEFT$(searchName$, 1)

  DO WHILE checkIdx <> -1
    IF RTRIM$(symbols(checkIdx).RecordName) = searchName$ THEN
      IF currentScopeID > 0 AND symbols(checkIdx).ScopeID = currentScopeID THEN
        return2 checkIdx
        findSymbol = 1
        EXIT FUNCTION
      END IF
      IF symbols(checkIdx).ScopeID = 0 THEN
        IF currentScopeID = 0 THEN
          IF globalIdx = -1 THEN globalIdx = checkIdx
        ELSE
          IF symbols(checkIdx).IsShared = 1 OR symbols(checkIdx).SubIndex <> 0 OR firstCh = "!" OR firstCh = "@" THEN
            IF globalIdx = -1 THEN globalIdx = checkIdx
          END IF
        END IF
      END IF
    END IF
    checkIdx = symbols(checkIdx).HashNext
  LOOP

  IF globalIdx <> -1 THEN
    return2 globalIdx
    findSymbol = 1
    EXIT FUNCTION
  END IF

END FUNCTION ' findSymbol

''''''''''''''''''''''''
FUNCTION findUdtIndex (passName$)

  returnExtraPrepare

  searchName$ = RTRIM$(passName$)

  FOR ii = 0 TO udtCount - 1
    IF RTRIM$(udts(ii).RecordName) = searchName$ THEN
      return2 ii
      findUdtIndex = 1
      EXIT FUNCTION
    END IF
  NEXT

END FUNCTION ' findUdtIndex

''''''''''''''''''''''''
FUNCTION flattenRebuildStr$ (startIdx, endIdx)

  outStr$ = ""
  FOR ii = startIdx TO endIdx
    outStr$ = outStr$ + retTokenText$(lineTokens$(ii))
    IF ii < endIdx THEN outStr$ = outStr$ + " "
  NEXT

  flattenRebuildStr$ = outStr$

END FUNCTION ' flattenRebuildStr$

''''''''''''''''''''''''
FUNCTION genAlignedCall (iatConst, backupReg, stackArgBytes AS LONG)

  ' stackArgBytes must be a multiple of 8

  ' Safety check to ensure stack argument allocation is aligned to 8-byte boundaries
  IF (stackArgBytes MOD 8) <> 0 THEN
    errStr$ = "FATAL ERROR: genAlignedCall tried to allocate " + LTRIM$(STR$(stackArgBytes)) + " stack argument bytes (not a multiple of 8) while compiling basic line " + retLineNumberStr$
    ESCAPETEXT errStr$
  END IF

  ' Helper function for calling external Windows API functions that require ABI compliance with 16-byte stack alignment and 32-byte shadow space

  DIM pushedFiller AS LONG
  DIM allocSize AS LONG
  DIM remainder AS LONG

  pushedFiller = 0

  ' Calculate total allocation (32 bytes shadow space + extra arguments)
  allocSize = 32 + stackArgBytes

  ' Ensure allocation size is a multiple of 16 to maintain stack alignment
  remainder = allocSize MOD 16
  IF remainder <> 0 THEN
    allocSize = allocSize + (16 - remainder)
  END IF

  ' Call updateStackAlignment to see if the stack is misaligned by 8 bytes
  IF updateStackAlignment = 0 THEN
    ' Dummy Push - Push a harmless register to snap the stack pointer to a 16-byte boundary
    opPushReg backupReg
    pushedFiller = 1
  END IF

  ' Shadow space allocation - Carve out the mandatory bytes for the Windows API scratchpad
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, allocSize, 64)
  stack.currentStackOffset = stack.currentStackOffset + allocSize
  ff = updateStackAlignment

  ' The API Call - Execute the OS function safely using the properly formatted stack
  ff = opCall(iatConst, CALLMODE_IAT)

  ' The Cleanup - Destroy the shadow space to restore the stack
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, allocSize, 64)
  stack.currentStackOffset = stack.currentStackOffset - allocSize
  ff = updateStackAlignment

  ' If we pushed a dummy register above to fix alignment, pop it back off to leave the stack exactly as we found it
  IF pushedFiller = 1 THEN
    opPopReg backupReg
  END IF

  genAlignedCall = 1

END FUNCTION ' genAlignedCall

''''''''''''''''''''''''
SUB genBlockTransfer (srcReg, destReg, lenReg)

  ' The gen prefix indicates a higher-level code generation helper used to reduce boilerplate

  ' Emits an x64 block copy by transferring data from a source address register to a
  ' destination address register for a specified length. This helper automatically
  ' manages architectural register assignment and provides a safety check to skip
  ' the operation if the length is zero

  opPushReg 6 ' Save non-volatile RSI
  opPushReg 7 ' Save non-volatile RDI
  opPushReg 1 ' Save volatile RCX

  ' Move to architectural string registers if not already there
  IF srcReg <> 6 THEN ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, srcReg, 64)
  IF destReg <> 7 THEN ff = opMov(OP_TYPE_REG, 7, OP_TYPE_REG, destReg, 64)
  IF lenReg <> 1 THEN ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, lenReg, 64)

  ' test rcx, rcx
  ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)

  ' jle .skip_copy
  jmpSkipCopyPos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  opFlag FLAG_CLD ' Ensure forward copying direction!

  ' rep movsb
  opString STR_MOVS, REP_REP, 8

  ' .skip_copy:
  patch8 jmpSkipCopyPos

  opPopReg 1
  opPopReg 7
  opPopReg 6

END SUB ' genBlockTransfer

''''''''''''''''''''''''
FUNCTION genLoadStringDesc (descReg, dataReg, lenReg)

  ' Extracts the Data Pointer and Length from a 24-byte string descriptor
  ' descReg contains the pointer to the descriptor. dataReg and lenReg receive the unpacked values.

  ' mov dataReg, [descReg] (Data)
  ff = opMov(OP_TYPE_REG, dataReg, OP_TYPE_MEM_REG, descReg, 64)

  ' mov lenReg, [descReg + 8] (Len)
  ff = opMov(OP_TYPE_REG, lenReg, OP_TYPE_MEM_REG_DISP8, descReg + (8 * 256), 64)

  genLoadStringDesc = 1

END FUNCTION ' genLoadStringDesc

''''''''''''''''''''''''
FUNCTION genSymbolRouteLea (destReg AS LONG, vIdx AS LONG)

  ' Automatically routes variable access to either global memory (RIP-relative) or local SUB/FUNCTION stack frames (RBP-relative)
  ' This prevents the frontend from needing massive boilerplate blocks to determine variable scope on every memory read/write

  DIM subIdx AS LONG
  DIM rbpOffset AS LONG
  DIM isValidLocal AS LONG

  IF symbols(vIdx).DataType = TYPE_UNDEFINED THEN
    ESCAPETEXT2 "GSRL FATAL IN genSymbolRouteLea", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(vIdx).RecordName)
  END IF

  isValidLocal = 0

  IF (symbols(vIdx).IsLocal = LOCAL_STANDARD OR symbols(vIdx).IsLocal = LOCAL_ABSOLUTE) AND symbols(vIdx).IsShared = 0 THEN
    IF symbols(vIdx).IsLocal = LOCAL_ABSOLUTE THEN
      rbpOffset = symbols(vIdx).LocalOffset
      isValidLocal = 1
    ELSE
      ff = findSubIndexByScope(symbols(vIdx).ScopeID)
      IF ff = 1 THEN
        subIdx = returnedData2
        rbpOffset = symbols(vIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56
        isValidLocal = 1
      END IF
    END IF

    IF isValidLocal = 1 THEN
      ff = opLea(OP_TYPE_REG, destReg, OP_TYPE_MEM_RBP, rbpOffset, 64)
      genSymbolRouteLea = 1
      EXIT FUNCTION
    END IF
  END IF

  ' Global fallback
  IF symbols(vIdx).DataType = TYPE_STRING AND symbols(vIdx).IsArray = 0 AND LEFT$(symbols(vIdx).RecordName, 1) <> "~" THEN
    ff = opMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64)
  ELSE
    ff = opLea(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64)
  END IF

  IF symbols(vIdx).DataType = TYPE_LABEL THEN
    addPatch PATCH_GOTO, ff, vIdx
  ELSE
    addPatch PATCH_VAR, ff, vIdx
  END IF

  genSymbolRouteLea = 1

END FUNCTION ' genSymbolRouteLea

''''''''''''''''''''''''
FUNCTION genSymbolRouteMov (destType AS LONG, destInfo AS LONG, srcType AS LONG, srcInfo AS _INTEGER64, opSize AS LONG, vIdx AS LONG)

  DIM subIdx AS LONG
  DIM rbpOffset AS LONG
  DIM fDestType AS LONG
  DIM fDestInfo AS LONG
  DIM fSrcType AS LONG
  DIM fSrcInfo AS _INTEGER64
  DIM isValidLocal AS LONG

  IF symbols(vIdx).DataType = TYPE_UNDEFINED THEN
    ESCAPETEXT2 "GSRM FATAL IN genSymbolRouteMov", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(vIdx).RecordName)
  END IF

  fDestType = destType
  fDestInfo = destInfo
  fSrcType = srcType
  fSrcInfo = srcInfo

  isValidLocal = 0

  IF (symbols(vIdx).IsLocal = LOCAL_STANDARD OR symbols(vIdx).IsLocal = LOCAL_ABSOLUTE) AND symbols(vIdx).IsShared = 0 THEN
    IF symbols(vIdx).IsLocal = LOCAL_ABSOLUTE THEN
      rbpOffset = symbols(vIdx).LocalOffset
      isValidLocal = 1
    ELSE
      ff = findSubIndexByScope(symbols(vIdx).ScopeID)
      IF ff = 1 THEN
        subIdx = returnedData2
        rbpOffset = symbols(vIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56
        isValidLocal = 1
      END IF
    END IF

    IF isValidLocal = 1 THEN
      IF destType = OP_TYPE_MEM_RIP THEN
        fDestType = OP_TYPE_MEM_RBP
        fDestInfo = rbpOffset
      END IF
      IF srcType = OP_TYPE_MEM_RIP THEN
        fSrcType = OP_TYPE_MEM_RBP
        fSrcInfo = rbpOffset
      END IF

      ' Local standalone strings and UDTs need their address (LEA) rather than value loaded, because
      ' their descriptors/structs reside inline on the stack instead of having a pointer in the global data segment
      IF (symbols(vIdx).DataType = TYPE_STRING OR symbols(vIdx).DataType = TYPE_UDT) AND symbols(vIdx).IsArray = 0 AND LEFT$(symbols(vIdx).RecordName, 1) <> "~" THEN
        IF srcType = OP_TYPE_MEM_RIP AND destType = OP_TYPE_REG THEN
          ff = opLea(OP_TYPE_REG, fDestInfo, OP_TYPE_MEM_RBP, rbpOffset, 64)
          genSymbolRouteMov = 1
          EXIT FUNCTION
        END IF
      END IF

      ff = opMov(fDestType, fDestInfo, fSrcType, fSrcInfo, opSize)
      genSymbolRouteMov = 1
      EXIT FUNCTION
    END IF
  END IF

  ' Global fallback
  ff = opMov(fDestType, fDestInfo, fSrcType, fSrcInfo, opSize)

  IF symbols(vIdx).DataType = TYPE_LABEL THEN
    addPatch PATCH_GOTO, ff, vIdx
  ELSE
    addPatch PATCH_VAR, ff, vIdx
  END IF

  genSymbolRouteMov = 1

END FUNCTION ' genSymbolRouteMov

''''''''''''''''''''''''
FUNCTION genSymbolRouteSSE (sseOpCode AS LONG, destType AS LONG, destInfo AS LONG, srcType AS LONG, srcInfo AS LONG, opMode AS LONG, vIdx AS LONG)

  DIM subIdx AS LONG
  DIM rbpOffset AS LONG
  DIM fDestType AS LONG
  DIM fDestInfo AS LONG
  DIM fSrcType AS LONG
  DIM fSrcInfo AS LONG
  DIM isValidLocal AS LONG

  IF symbols(vIdx).DataType = TYPE_UNDEFINED THEN
    ESCAPETEXT2 "GSRS FATAL IN genSymbolRouteSSE", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(vIdx).RecordName)
  END IF

  fDestType = destType
  fDestInfo = destInfo
  fSrcType = srcType
  fSrcInfo = srcInfo

  isValidLocal = 0

  IF (symbols(vIdx).IsLocal = LOCAL_STANDARD OR symbols(vIdx).IsLocal = LOCAL_ABSOLUTE) AND symbols(vIdx).IsShared = 0 THEN
    IF symbols(vIdx).IsLocal = LOCAL_ABSOLUTE THEN
      rbpOffset = symbols(vIdx).LocalOffset
      isValidLocal = 1
    ELSE
      ff = findSubIndexByScope(symbols(vIdx).ScopeID)
      IF ff = 1 THEN
        subIdx = returnedData2
        rbpOffset = symbols(vIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56
        isValidLocal = 1
      END IF
    END IF

    IF isValidLocal = 1 THEN
      IF destType = OP_TYPE_MEM_RIP THEN
        fDestType = OP_TYPE_MEM_RBP
        fDestInfo = rbpOffset
      END IF
      IF srcType = OP_TYPE_MEM_RIP THEN
        fSrcType = OP_TYPE_MEM_RBP
        fSrcInfo = rbpOffset
      END IF

      ff = opSSE(sseOpCode, fDestType, fDestInfo, fSrcType, fSrcInfo, opMode)
      genSymbolRouteSSE = 1
      EXIT FUNCTION
    END IF
  END IF

  ' Global fallback
  ff = opSSE(sseOpCode, fDestType, fDestInfo, fSrcType, fSrcInfo, opMode)

  IF symbols(vIdx).DataType = TYPE_LABEL THEN
    addPatch PATCH_GOTO, ff, vIdx
  ELSE
    addPatch PATCH_VAR, ff, vIdx
  END IF

  genSymbolRouteSSE = 1

END FUNCTION ' genSymbolRouteSSE

''''''''''''''''''''''''
FUNCTION hashString (wStr$)

  hVal = 5381
  sLen = LEN(wStr$)
  FOR ii = 1 TO sLen
    hVal = ((hVal * 33) + ASC(wStr$, ii)) AND SYMBOL_HASH_MASK
  NEXT

  hashString = hVal

END FUNCTION ' hashString

''''''''''''''''''''''''
FUNCTION hexLen$ (wVal, wLen)

  outStr$ = HEX$(wVal)
  FOR ii = 0 TO 2
    IF LEN(outStr$) < wLen THEN
      outStr$ = "0" + outStr$
    END IF
  NEXT

  hexLen$ = outStr$

END FUNCTION ' hexLen$

''''''''''''''''''''''''
SUB hoistIntrinsics

  DIM hasIntrinsics AS LONG
  DIM iSearch AS LONG
  DIM iCheck AS LONG
  DIM deepestStart AS LONG
  DIM deepestEnd AS LONG
  DIM foundDeeper AS LONG
  DIM tVal AS LONG
  DIM isIntrinsic AS LONG
  DIM isZeroArg AS LONG
  DIM repVar$

  DO
    hasIntrinsics = 0
    deepestStart = -1

    ' Pass 1: Find the first migrated intrinsic
    FOR iSearch = 0 TO lineTokenCount - 1
      tVal = lineTokenVals(iSearch)
      isIntrinsic = 0

      ' Only trap intrinsics that have been successfully migrated to the Hoisting Architecture
      SELECT CASE tVal
        CASE TOK_HEX, TOK_SPACE, TOK_CHR, TOK_LEN, TOK_ASC, TOK_LTRIM, TOK_RTRIM, TOK_UCASE, TOK_LEFT, TOK_RIGHT, TOK_STR, TOK_VAL, TOK_MID, TOK_INT, TOK_ATN, TOK_KEYDOWN, TOK_INKEY, TOK_INKEYF, TOK_PEEK, TOK_LOF, TOK_POINT, TOK_RGB32, TOK_SIN, TOK_COS, TOK_TIMER, TOK_MOUSEINPUT, TOK_MOUSEX, TOK_MOUSEY, TOK_MOUSEBUTTON, TOK_MOUSEWHEEL
          isIntrinsic = 1
      END SELECT

      IF isIntrinsic = 1 THEN
        hasIntrinsics = 1
        deepestStart = iSearch
        EXIT FOR
      END IF
    NEXT

    IF hasIntrinsics = 0 THEN EXIT DO

    ' Pass 2: We found an intrinsic. Drill down to find the deepest nested one
    DO
      isZeroArg = 0
      IF lineTokenVals(deepestStart) = TOK_INKEY OR lineTokenVals(deepestStart) = TOK_INKEYF OR lineTokenVals(deepestStart) = TOK_TIMER OR lineTokenVals(deepestStart) = TOK_MOUSEINPUT OR lineTokenVals(deepestStart) = TOK_MOUSEX OR lineTokenVals(deepestStart) = TOK_MOUSEY OR lineTokenVals(deepestStart) = TOK_MOUSEWHEEL THEN
        isZeroArg = 1
      END IF

      IF isZeroArg = 1 THEN
        deepestEnd = deepestStart
      ELSE
        IF deepestStart + 1 < lineTokenCount THEN
          IF lineTokenVals(deepestStart + 1) = 256 + ASC("(") THEN
            ff = findMatchingParen(deepestStart + 1, lineTokenCount - 1)
            IF ff = 0 THEN
              throwCompilerError "MISSING ) ON INTRINSIC", ASIS, 0
              EXIT SUB
            END IF
            deepestEnd = returnedData2
          ELSE
            throwCompilerError "INTRINSIC MISSING (", ASIS, 0
            EXIT SUB
          END IF
        ELSE
          throwCompilerError "INTRINSIC MISSING (", ASIS, 0
          EXIT SUB
        END IF
      END IF

      foundDeeper = 0
      FOR iCheck = deepestStart + 2 TO deepestEnd - 1
        tVal = lineTokenVals(iCheck)
        isIntrinsic = 0

        SELECT CASE tVal

          CASE TOK_HEX, TOK_SPACE, TOK_CHR, TOK_LEN, TOK_ASC, TOK_LTRIM, TOK_RTRIM, TOK_UCASE, TOK_LEFT, TOK_RIGHT, TOK_STR, TOK_VAL, TOK_MID, TOK_INT, TOK_ATN, TOK_KEYDOWN, TOK_INKEY, TOK_INKEYF, TOK_PEEK, TOK_LOF, TOK_POINT, TOK_RGB32, TOK_SIN, TOK_COS, TOK_TIMER, TOK_MOUSEINPUT, TOK_MOUSEX, TOK_MOUSEY, TOK_MOUSEBUTTON, TOK_MOUSEWHEEL
            isIntrinsic = 1

        END SELECT ' tVal

        IF isIntrinsic = 1 THEN
          foundDeeper = 1
          deepestStart = iCheck
          EXIT FOR
        END IF
      NEXT

      IF foundDeeper = 0 THEN EXIT DO
    LOOP

    ' Phase 3: Route the deepest intrinsic to its Architect parser
    repVar$ = parseIntrinsic$(deepestStart, deepestEnd, ALIM)
    IF repVar$ = "" OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      EXIT SUB
    END IF

    ' Phase 4: Flatten the array to replace the intrinsic block with the generated variable
    collapseTokens deepestStart, deepestEnd, repVar$
  LOOP

END SUB ' hoistIntrinsics

''''''''''''''''''''''''
SUB initColors

  sysColor.flashTextClr = 14
  sysColor.gray = 8
  sysColor.focusBorder = 10

END SUB ' initColors

''''''''''''''''''''''''
SUB initFileNames

  fileNameBMP$ = "PALETTE.BMP"
  fileNameCode$ = "CODE.BAS"
  fileNameOut$ = "Output.exe"
  fileNameErr$ = "ErrorReport.txt"

END SUB ' initFileNames

''''''''''''''''''''''''
SUB initIntrinsics

  intrinsicCount = 0

  addIntrinsic "ASC", TYPE_LONG
  addIntrinsic "ATN", TYPE_DOUBLE
  addIntrinsic "CHR$", TYPE_STRING
  addIntrinsic "HEX$", TYPE_STRING
  addIntrinsic "INT", TYPE_LONG
  addIntrinsic "LEFT$", TYPE_STRING
  addIntrinsic "LEN", TYPE_LONG
  addIntrinsic "LOF", TYPE_LONG
  addIntrinsic "LTRIM$", TYPE_STRING
  addIntrinsic "MID$", TYPE_STRING
  addIntrinsic "PEEK", TYPE_LONG
  addIntrinsic "POINT", TYPE_LONG
  addIntrinsic "RIGHT$", TYPE_STRING
  addIntrinsic "RTRIM$", TYPE_STRING
  addIntrinsic "SPACE$", TYPE_STRING
  addIntrinsic "STR$", TYPE_STRING
  addIntrinsic "UCASE$", TYPE_STRING
  addIntrinsic "VAL", TYPE_LONG
  addIntrinsic "_KEYDOWN", TYPE_LONG
  addIntrinsic "_RGB32", TYPE_LONG
  addIntrinsic "SIN", TYPE_DOUBLE
  addIntrinsic "COS", TYPE_DOUBLE
  addIntrinsic "TIMER", TYPE_DOUBLE
  addIntrinsic "_MOUSEINPUT", TYPE_LONG
  addIntrinsic "_MOUSEX", TYPE_LONG
  addIntrinsic "_MOUSEY", TYPE_LONG
  addIntrinsic "_MOUSEBUTTON", TYPE_LONG
  addIntrinsic "_MOUSEWHEEL", TYPE_LONG

END SUB ' initIntrinsics

''''''''''''''''''''''''
SUB initKeyMapping

  keyMappingCount = 0

  ' Uppercase A-Z
  FOR ii = 65 TO 90
    keyMapping(keyMappingCount).qbCode = ii
    keyMapping(keyMappingCount).vkCode = ii
    keyMappingCount = keyMappingCount + 1
  NEXT

  ' Lowercase a-z
  FOR ii = 97 TO 122
    keyMapping(keyMappingCount).qbCode = ii
    keyMapping(keyMappingCount).vkCode = ii - 32
    keyMappingCount = keyMappingCount + 1
  NEXT

END SUB ' initKeyMapping

''''''''''''''''''''''''
SUB initKeywords

  DIM flagDirective AS LONG
  flagDirective = 1 ' Use if a preprocessor command with a hashtag

  addKeyword "AND", TOK_AND, 0
  addKeyword "ANY", TOK_ANY, 0
  addKeyword "AS", TOK_AS, 0
  addKeyword "ASC", TOK_ASC, 0
  addKeyword "ATN", TOK_ATN, 0
  addKeyword "BEEP", TOK_BEEP, 0
  addKeyword "BYTE", TOK_BYTE, 0
  addKeyword "CALL", TOK_CALL, 0
  addKeyword "CASE", TOK_CASE, 0
  addKeyword "CHR$", TOK_CHR, 0
  addKeyword "#CLASSIC", TOK_CLASSIC, flagDirective
  addKeyword "CLS", TOK_CLS, 0
  addKeyword "COLOR", TOK_COLOR, 0
  addKeyword "COMMON", TOK_COMMON, 0
  addKeyword "DECLARE", TOK_DECLARE, 0
  addKeyword "DEF", TOK_DEF, 0
  addKeyword "#DEFINT", TOK_DEFINT, flagDirective
  addKeyword "DIM", TOK_DIM, 0
  addKeyword "DO", TOK_DO, 0
  addKeyword "DOUBLE", TOK_DOUBLE, 0
  addKeyword "DSTRING", TOK_DSTRING, 0
  addKeyword "ELSE", TOK_ELSE, 0
  addKeyword "END", TOK_END, 0
  addKeyword "ERROR", TOK_ERROR, 0
  addKeyword "EXIT", TOK_EXIT, 0
  addKeyword "_FONT", TOK_FONT, 0
  addKeyword "FOR", TOK_FOR, 0
  addKeyword "_FULLSCREEN", TOK_FULLSCREEN, 0
  addKeyword "FUNCTION", TOK_FUNCTION, 0
  addKeyword "#GDOUBLE", TOK_GDOUBLE, flagDirective
  addKeyword "GLOBAL", TOK_GLOBAL, 0
  addKeyword "GOTO", TOK_GOTO, 0
  addKeyword "#GRAPHICS", TOK_GRAPHICS, flagDirective
  addKeyword "IF", TOK_IF, 0
  addKeyword "INKEY$", TOK_INKEY, 0
  addKeyword "INKEYF$", TOK_INKEYF, 0
  addKeyword "INPUT", TOK_INPUT, 0
  addKeyword "INT", TOK_INT, 0
  addKeyword "INTEGER", TOK_INTEGER, 0
  addKeyword "INTEGER64", TOK_INTEGER64, 0
  addKeyword "_KEYDOWN", TOK_KEYDOWN, 0
  addKeyword "LEFT$", TOK_LEFT, 0
  addKeyword "LEN", TOK_LEN, 0
  addKeyword "LET", TOK_LET, 0
  addKeyword "LINE", TOK_LINE, 0
  addKeyword "LOCATE", TOK_LOCATE, 0
  addKeyword "LONG", TOK_LONG, 0
  addKeyword "LOOP", TOK_LOOP, 0
  addKeyword "LTRIM$", TOK_LTRIM, 0
  addKeyword "MID$", TOK_MID, 0
  addKeyword "NEXT", TOK_NEXT, 0
  addKeyword "NOT", TOK_NOT, 0
  addKeyword "ON", TOK_ON, 0
  addKeyword "OR", TOK_OR, 0
  addKeyword "PRINT", TOK_PRINT, 0
  addKeyword "PSET", TOK_PSET, 0
  addKeyword "RESUME", TOK_RESUME, 0
  addKeyword "RETURN", TOK_RETURN, 0
  addKeyword "RIGHT$", TOK_RIGHT, 0
  addKeyword "RTRIM$", TOK_RTRIM, 0
  addKeyword "SCREEN", TOK_SCREEN, 0
  addKeyword "SELECT", TOK_SELECT, 0
  addKeyword "SHARED", TOK_SHARED, 0
  addKeyword "SINGLE", TOK_SINGLE, 0
  addKeyword "STEP", TOK_STEP, 0
  addKeyword "STR$", TOK_STR, 0
  addKeyword "STRING", TOK_STRING, 0
  addKeyword "SUB", TOK_SUB, 0
  addKeyword "THEN", TOK_THEN, 0
  addKeyword "TO", TOK_TO, 0
  addKeyword "TYPE", TOK_TYPE, 0
  addKeyword "UCASE$", TOK_UCASE, 0
  addKeyword "UNSIGNED", TOK_UNSIGNED, 0
  addKeyword "UNTIL", TOK_UNTIL, 0
  addKeyword "VAL", TOK_VAL, 0

  addKeyword "CINT", TOK_CINT, 0
  addKeyword "CLNG", TOK_CLNG, 0
  addKeyword "CSNG", TOK_CSNG, 0
  addKeyword "CDBL", TOK_CDBL, 0
  addKeyword "HEX$", TOK_HEX, 0
  addKeyword "SPACE$", TOK_SPACE, 0
  addKeyword "DEFINT", TOK_DEFINT_NORM, 0
  addKeyword "POKE", TOK_POKE, 0
  addKeyword "PEEK", TOK_PEEK, 0
  addKeyword "GOSUB", TOK_GOSUB, 0
  addKeyword "#STRINGSTRICT", TOK_STRINGSTRICT, flagDirective
  addKeyword "GET", TOK_GET, 0
  addKeyword "PUT", TOK_PUT, 0
  addKeyword "_DISPLAY", TOK_DISPLAY, 0
  addKeyword "_LIMIT", TOK_LIMIT, 0
  addKeyword "OPEN", TOK_OPEN, 0
  addKeyword "CLOSE", TOK_CLOSE, 0
  addKeyword "LOF", TOK_LOF, 0
  addKeyword "BINARY", TOK_BINARY, 0
  addKeyword "RANDOM", TOK_RANDOM, 0
  addKeyword "KILL", TOK_KILL, 0
  addKeyword "_DISPLAYI", TOK_DISPLAYI, 0
  addKeyword "POINT", TOK_POINT, 0
  addKeyword "_PALETTECOLOR", TOK_PALETTECOLOR, 0
  addKeyword "_RGB32", TOK_RGB32, 0
  addKeyword "STOP", TOK_STOP, 0
  addKeyword "SIN", TOK_SIN, 0
  addKeyword "COS", TOK_COS, 0
  addKeyword "CIRCLE", TOK_CIRCLE, 0
  addKeyword "RANDOMIZE", TOK_RANDOMIZE, 0
  addKeyword "TIMER", TOK_TIMER, 0
  addKeyword "WHILE", TOK_WHILE, 0
  addKeyword "WEND", TOK_WEND, 0
  addKeyword "DATA", TOK_DATA, 0
  addKeyword "READ", TOK_READ, 0
  addKeyword "RESTORE", TOK_RESTORE, 0
  addKeyword "PALETTE", TOK_PALETTE, 0
  addKeyword "#EMERALD", TOK_EMERALD, flagDirective
  addKeyword "REM", TOK_REM, 0
  addKeyword "$STATIC", TOK_STATIC, flagDirective
  addKeyword "$DYNAMIC", TOK_DYNAMIC, flagDirective
  addKeyword "STATIC", TOK_STATIC, 0
  addKeyword "DYNAMIC", TOK_DYNAMIC, 0
  addKeyword "REDIM", TOK_REDIM, 0

  addKeyword "_MOUSEINPUT", TOK_MOUSEINPUT, 0
  addKeyword "_MOUSEX", TOK_MOUSEX, 0
  addKeyword "_MOUSEY", TOK_MOUSEY, 0
  addKeyword "_MOUSEBUTTON", TOK_MOUSEBUTTON, 0
  addKeyword "_MOUSEWHEEL", TOK_MOUSEWHEEL, 0

END SUB ' initKeywords

''''''''''''''''''''''''
SUB initLayout

  editor.StartY = 15

  editor.CursorY = 1
  editor.ScrollY = 1
  editor.LastLine = 1
  editor.SelectStartY = 1

  editorText$(0) = "LINE 0: YOU SHOULD NEVER SEE THIS"
  compileText$(0) = "LINE 0: YOU SHOULD NEVER SEE THIS"

  statusMsg$(0) = "LINE 0: YOU SHOULD NEVER SEE THIS"
  statusMsgCount = 1
  editor.StatusScrollY = 1
  editor.StatusSelectedIndex = 0

  layout.FramebufSize = FRAMEBUF_MAX_WIDTH * FRAMEBUF_MAX_HEIGHT
  layout.GfxBufEntrySize = 256

  tempSize = layout.GfxBufEntrySize
  shiftCount = 0
  DO WHILE tempSize > 1
    tempSize = tempSize \ 2
    shiftCount = shiftCount + 1
  LOOP
  layout.GfxBufEntryShift = shiftCount

  IF (2 ^ layout.GfxBufEntryShift) <> layout.GfxBufEntrySize THEN
    ESCAPETEXT "ERROR: GfxBufEntryShift calculation failed"
  END IF

END SUB ' initLayout

''''''''''''''''''''''''
SUB initPalettesBmp

  ' 0-15 Standard VGA-style palette
  bmpPal256(0, palRED) = 0: bmpPal256(0, palGREEN) = 0: bmpPal256(0, palBLUE) = 0 ' Black
  bmpPal256(1, palRED) = 0: bmpPal256(1, palGREEN) = 0: bmpPal256(1, palBLUE) = 170 ' Blue
  bmpPal256(2, palRED) = 0: bmpPal256(2, palGREEN) = 170: bmpPal256(2, palBLUE) = 0 ' Green
  bmpPal256(3, palRED) = 0: bmpPal256(3, palGREEN) = 170: bmpPal256(3, palBLUE) = 170 ' Cyan
  bmpPal256(4, palRED) = 170: bmpPal256(4, palGREEN) = 0: bmpPal256(4, palBLUE) = 0 ' Red
  bmpPal256(5, palRED) = 170: bmpPal256(5, palGREEN) = 0: bmpPal256(5, palBLUE) = 170 ' Magenta
  bmpPal256(6, palRED) = 170: bmpPal256(6, palGREEN) = 85: bmpPal256(6, palBLUE) = 0 ' Brown
  bmpPal256(7, palRED) = 170: bmpPal256(7, palGREEN) = 170: bmpPal256(7, palBLUE) = 170 ' Light Gray
  bmpPal256(8, palRED) = 85: bmpPal256(8, palGREEN) = 85: bmpPal256(8, palBLUE) = 85 ' Dark Gray
  bmpPal256(9, palRED) = 85: bmpPal256(9, palGREEN) = 85: bmpPal256(9, palBLUE) = 255 ' Light Blue
  bmpPal256(10, palRED) = 85: bmpPal256(10, palGREEN) = 255: bmpPal256(10, palBLUE) = 85 ' Light Green
  bmpPal256(11, palRED) = 85: bmpPal256(11, palGREEN) = 255: bmpPal256(11, palBLUE) = 255 ' Light Cyan
  bmpPal256(12, palRED) = 255: bmpPal256(12, palGREEN) = 85: bmpPal256(12, palBLUE) = 85 ' Light Red
  bmpPal256(13, palRED) = 255: bmpPal256(13, palGREEN) = 85: bmpPal256(13, palBLUE) = 255 ' Light Magenta
  bmpPal256(14, palRED) = 255: bmpPal256(14, palGREEN) = 255: bmpPal256(14, palBLUE) = 85 ' Yellow
  bmpPal256(15, palRED) = 255: bmpPal256(15, palGREEN) = 255: bmpPal256(15, palBLUE) = 255 ' Bright White

  ' 16-191 Red spectrum: dim red to bright red
  FOR ii = 16 TO 191
    redVal = ((ii - 16) * 255) \ 175
    bmpPal256(ii, palRED) = redVal
    bmpPal256(ii, palGREEN) = 0
    bmpPal256(ii, palBLUE) = 0
  NEXT

  ' 192-255 Blue spectrum: dark blue to bright blue
  FOR ii = 192 TO 255
    blueVal = ((ii - 192) * 255) \ 63
    bmpPal256(ii, palRED) = 0
    bmpPal256(ii, palGREEN) = 0
    bmpPal256(ii, palBLUE) = blueVal
  NEXT

END SUB ' initPalettesBmp

''''''''''''''''''''''''
SUB initPalettesOutput

  ' 0-15 Standard VGA-style palette for output.exe
  outputPal(0, palRED) = 0: outputPal(0, palGREEN) = 0: outputPal(0, palBLUE) = 0 ' Black
  outputPal(1, palRED) = 0: outputPal(1, palGREEN) = 0: outputPal(1, palBLUE) = 170 ' Blue
  outputPal(2, palRED) = 0: outputPal(2, palGREEN) = 170: outputPal(2, palBLUE) = 0 ' Green
  outputPal(3, palRED) = 0: outputPal(3, palGREEN) = 170: outputPal(3, palBLUE) = 170 ' Cyan
  outputPal(4, palRED) = 170: outputPal(4, palGREEN) = 0: outputPal(4, palBLUE) = 0 ' Red
  outputPal(5, palRED) = 170: outputPal(5, palGREEN) = 0: outputPal(5, palBLUE) = 170 ' Magenta
  outputPal(6, palRED) = 170: outputPal(6, palGREEN) = 85: outputPal(6, palBLUE) = 0 ' Brown
  outputPal(7, palRED) = 170: outputPal(7, palGREEN) = 170: outputPal(7, palBLUE) = 170 ' Light Gray
  outputPal(8, palRED) = 85: outputPal(8, palGREEN) = 85: outputPal(8, palBLUE) = 85 ' Dark Gray
  outputPal(9, palRED) = 85: outputPal(9, palGREEN) = 85: outputPal(9, palBLUE) = 255 ' Light Blue
  outputPal(10, palRED) = 85: outputPal(10, palGREEN) = 255: outputPal(10, palBLUE) = 85 ' Light Green
  outputPal(11, palRED) = 85: outputPal(11, palGREEN) = 255: outputPal(11, palBLUE) = 255 ' Light Cyan
  outputPal(12, palRED) = 255: outputPal(12, palGREEN) = 85: outputPal(12, palBLUE) = 85 ' Light Red
  outputPal(13, palRED) = 255: outputPal(13, palGREEN) = 85: outputPal(13, palBLUE) = 255 ' Light Magenta
  outputPal(14, palRED) = 255: outputPal(14, palGREEN) = 255: outputPal(14, palBLUE) = 85 ' Yellow
  outputPal(15, palRED) = 255: outputPal(15, palGREEN) = 255: outputPal(15, palBLUE) = 255 ' Bright White

  FOR ii = 16 TO 255
    outputPal(ii, palRED) = 0
    outputPal(ii, palGREEN) = 0
    outputPal(ii, palBLUE) = 0
  NEXT

END SUB ' initPalettesOutput

''''''''''''''''''''''''
SUB initStackLayout

  stack.currentStackOffset = 0
  ff = updateStackAlignment

  '''' Console / User Code Frame
  ' This frame is used by the main execution thread (user BASIC code)
  ' It must accommodate Win64 shadow space (32 bytes) plus all local variables
  ' used by TIRA backend API calls.

  currentFrameSize = 32 ' Win64 shadow space

  ' Align the frame and save to consoleFrameSize
  stack.consoleFrameSize = alignStackFrame

  '''' Graphics Window Setup Frame
  ' Windows x64 ABI requires 32 bytes of shadow space at the bottom (RSP + 0 to RSP + 31)
  currentFrameSize = 32

  '''' Argument slots for CreateWindowExA (Must be contiguous for ABI)
  ' Arguments 5-12 on stack: X, Y, Width, Height, Parent, Menu, Instance, Param
  ' Stack Layout for Args: +32, +40, +48, +56, +64, +72, +80, +88

  stack.SETUP_SLOT_X = addStackSpace(8)
  stack.SETUP_SLOT_Y = addStackSpace(8)
  stack.SETUP_SLOT_NWIDTH = addStackSpace(8)
  stack.SETUP_SLOT_NHEIGHT = addStackSpace(8)
  stack.SETUP_SLOT_HWNDPARENT = addStackSpace(8)
  stack.SETUP_SLOT_HMENU = addStackSpace(8)
  stack.SETUP_SLOT_CREATE_HINSTANCE = addStackSpace(8)
  stack.SETUP_SLOT_LPPARAM = addStackSpace(8)

  '''' Local Variables (Scratch Space)
  ' RECT structure used for AdjustWindowRectEx calculation
  stack.SETUP_SLOT_RECT = addStackSpace(16)

  ' WNDCLASSEX structure (80 bytes)
  stack.SETUP_SLOT_WNDCLASSEX = addStackSpace(80)
  stack.SETUP_SLOT_STYLE = stack.SETUP_SLOT_WNDCLASSEX + 4
  stack.SETUP_SLOT_LPFNWNDPROC = stack.SETUP_SLOT_WNDCLASSEX + 8
  stack.SETUP_SLOT_CBCLSEXTRA = stack.SETUP_SLOT_WNDCLASSEX + 16
  stack.SETUP_SLOT_CBWNDEXTRA = stack.SETUP_SLOT_WNDCLASSEX + 20
  stack.SETUP_SLOT_WNDCLASSEX_HINSTANCE = stack.SETUP_SLOT_WNDCLASSEX + 24
  stack.SETUP_SLOT_HICON = stack.SETUP_SLOT_WNDCLASSEX + 32
  stack.SETUP_SLOT_HCURSOR = stack.SETUP_SLOT_WNDCLASSEX + 40
  stack.SETUP_SLOT_HBRBACKGROUND = stack.SETUP_SLOT_WNDCLASSEX + 48
  stack.SETUP_SLOT_LPSZMENUNAME = stack.SETUP_SLOT_WNDCLASSEX + 56
  stack.SETUP_SLOT_LPSZCLASSNAME = stack.SETUP_SLOT_WNDCLASSEX + 64
  stack.SETUP_SLOT_HICONSM = stack.SETUP_SLOT_WNDCLASSEX + 72

  ' Local variables for setup
  stack.SETUP_SLOT_HINSTANCE = addStackSpace(8)
  stack.SETUP_SLOT_HWND = addStackSpace(8)

  ' DIB Section requires BITMAPINFOHEADER (40 bytes) + 256 RGBQUADs (1024 bytes) = 1064 bytes
  stack.SETUP_SLOT_BITMAPINFO = addStackSpace(1064)

  ' Allocate space for the MSG structure used in the graphics message loop (48 bytes)
  stack.GRAPHICS_MSG_SLOT = addStackSpace(48)

  ' Align the setup frame to 16 bytes, adding 8 for the return address alignment
  stack.GFX_SETUP_FRAME = alignStackFrame

  '''' Graphics WndProc frame
  ' Must reserve 32 shadow space bytes plus exact local slots to prevent GDI from corrupting local memory variables
  currentFrameSize = 32

  stack.WNDPROC_SLOT_PAINTSTRUCT = addStackSpace(72)
  stack.WNDPROC_SLOT_PAINTSTRUCT_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_MSG = addStackSpace(8)
  stack.WNDPROC_SLOT_WPARAM = addStackSpace(8)
  stack.WNDPROC_SLOT_LPARAM = addStackSpace(8)
  stack.WNDPROC_SLOT_RET = addStackSpace(8)

  ' Local variables for WndProc
  stack.WNDPROC_SLOT_FB_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_FB_Y = addStackSpace(8)
  stack.WNDPROC_SLOT_FB_X = addStackSpace(8)
  stack.WNDPROC_SLOT_HDC = addStackSpace(8)
  stack.WNDPROC_SLOT_COUNT = addStackSpace(8)
  stack.WNDPROC_SLOT_BASE = addStackSpace(8)
  stack.WNDPROC_SLOT_HWND = addStackSpace(8)

  ' Memory DC handling slots
  stack.WNDPROC_SLOT_MEMDC = addStackSpace(8)
  stack.WNDPROC_SLOT_HBITMAP = addStackSpace(8)
  stack.WNDPROC_SLOT_OLD_HBITMAP = addStackSpace(8)
  stack.WNDPROC_SLOT_HFONT = addStackSpace(8)
  stack.WNDPROC_SLOT_OLD_HFONT = addStackSpace(8)
  stack.WNDPROC_SLOT_FONT_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_BITMAPINFO = addStackSpace(1064)

  ' Ephemeral calculation slots
  stack.WNDPROC_SLOT_PIX_B = addStackSpace(8)
  stack.WNDPROC_SLOT_PIX_L = addStackSpace(8)
  stack.WNDPROC_SLOT_PAL_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_COLOR_ADDR = addStackSpace(8)
  stack.WNDPROC_SLOT_COLOR = addStackSpace(8)
  stack.WNDPROC_SLOT_BASE_ITR = addStackSpace(8)
  stack.WNDPROC_SLOT_CNT_ITR = addStackSpace(8)
  stack.WNDPROC_SLOT_X_VAL = addStackSpace(8)
  stack.WNDPROC_SLOT_Y_VAL = addStackSpace(8)
  stack.WNDPROC_SLOT_STR_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_LEN_VAL = addStackSpace(8)
  stack.WNDPROC_SLOT_MAPPED_KEY = addStackSpace(8)
  stack.WNDPROC_SLOT_KEY_STATE = addStackSpace(8)

  ' Input parsing slots
  stack.WNDPROC_SLOT_CHAR_HEAD_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_CHAR_HEAD_VAL = addStackSpace(8)
  stack.WNDPROC_SLOT_CHAR_NEXTHEAD = addStackSpace(8)
  stack.WNDPROC_SLOT_CHAR_TAIL_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_CHAR_TAIL_VAL = addStackSpace(8)
  stack.WNDPROC_SLOT_CHAR_BUF_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_CHAR_TARGET = addStackSpace(8)

  ' Align the WndProc frame to 16 bytes, adding 8 for the return address alignment
  stack.GFX_WNDPROC_FRAME = alignStackFrame

  ' Restore currentFrameSize to the console frame size so emitPrologue/emitEpilogue use the correct size
  currentFrameSize = stack.consoleFrameSize

END SUB ' initStackLayout

''''''''''''''''''''''''
SUB initSymbolHash

  FOR ii = 0 TO SYMBOL_HASH_MASK
    symHash(ii) = -1
  NEXT

END SUB ' initSymbolHash

''''''''''''''''''''''''
FUNCTION keyCheck (wStr$) ' KeyCheck fast (Follow up with waitKeyRelease to use as slow option)

  wStr$ = UCASE$(wStr$) ' The character that's being checked for. Should be sent uppercase, but just in case
  ' since _KEYDOWN does not return a value, this function polls for key presses and return the value pressed
  ' This function will also help keep track of the special codes that keyDown uses. Only the
  ' codes that have specifically been entered, plus a-z, A-Z (calculated by formula) will work
  ' Returns the value of the key pressed. if keyCheck(whatever$) works just fine, because it
  ' checks to see if the return is greater than zero

  rVal = 0 ' In case we want to copy into a global "last key pressed" tracker

  IF wStr$ = "*" THEN ' * KEY
    IF _KEYDOWN(42) THEN
      keyCheck = 42
      EXIT FUNCTION
    END IF
  END IF

  IF wStr$ = "ESC" THEN ' Escape key
    IF _KEYDOWN(27) THEN
      keyCheck = 27
      EXIT FUNCTION
    END IF
  END IF

  IF wStr$ = "SPACE" THEN ' Space key
    IF _KEYDOWN(32) THEN
      keyCheck = 32
      EXIT FUNCTION
    END IF
  END IF

  IF wStr$ = "TAB" THEN ' Tab key
    IF _KEYDOWN(9) THEN
      keyCheck = 9
      EXIT FUNCTION
    END IF
  END IF

  ' Detect a-z, A-Z, these match ASCII exactly
  IF LEN(wStr$) = 1 THEN ' Handles characters A-Z, uppercase A is 65
    wVal = ASC(wStr$)
    IF ((wVal >= 65) AND (wVal <= 90)) OR ((wVal >= 97) AND (wVal <= 122)) THEN
      IF _KEYDOWN(wVal) OR _KEYDOWN(wVal + 32) THEN ' The +32 is for lowercase
        keyCheck = wVal
        EXIT FUNCTION
      END IF
    END IF
  END IF

  IF LEN(wStr$) = 2 AND MID$(wStr$, 1, 1) = "F" THEN ' Handles characters A-Z, uppercase A is 65

    SELECT CASE MID$(wStr$, 2, 1)

      CASE "1": rVal = 15104
      CASE "2": rVal = 15360
      CASE "3": rVal = 15616
      CASE "4": rVal = 15872
      CASE "5": rVal = 16128
      CASE "6": rVal = 16384
      CASE "7": rVal = 16640
      CASE "8": rVal = 16896
      CASE "9": rVal = 17152
      CASE "A": rVal = 17408
      CASE "B": rVal = 34048
      CASE "C": rVal = 34304
      CASE ELSE: EXIT FUNCTION

    END SELECT ' MID$(wStr$, 2, 1)

    IF _KEYDOWN(rVal) THEN
      keyCheck = rVal
      EXIT FUNCTION
    ELSE
      keyCheck = 0
      EXIT FUNCTION
    END IF

  END IF ' a-z, A-Z

  IF wStr$ = "0" THEN ' KEY 0, KEY INS
    IF _KEYDOWN(48) OR _KEYDOWN(20992) THEN rVal = 48
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  ' Arrow keys and number pad for controls (not used yet)
  IF wStr$ = "2" OR wStr$ = "DOWN" THEN
    IF _KEYDOWN(50) OR _KEYDOWN(20480) THEN rVal = 50 ' KEY 2, KEY DOWN
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "3" THEN
    IF _KEYDOWN(51) OR _KEYDOWN(20736) THEN rVal = 51 ' KEY 3
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "4" OR wStr$ = "LEFT" THEN
    IF _KEYDOWN(52) OR _KEYDOWN(19200) THEN rVal = 52 ' KEY 4, KEY LEFT
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "6" OR wStr$ = "RIGHT" THEN
    IF _KEYDOWN(54) OR _KEYDOWN(19712) THEN rVal = 54 ' KEY 6, KEY RIGHT
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "8" OR wStr$ = "UP" THEN
    IF _KEYDOWN(56) OR _KEYDOWN(18432) THEN rVal = 56 ' KEY 8, KEY UP
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  ' Key - or key _
  IF wStr$ = "-" THEN
    IF _KEYDOWN(45) OR _KEYDOWN(95) THEN rVal = 45
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  ' Key = or key +
  IF wStr$ = "=" THEN
    IF _KEYDOWN(61) OR _KEYDOWN(43) THEN rVal = 61
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  ' Key \ (right above enter on the keyboard)
  IF wStr$ = "\" THEN
    IF _KEYDOWN(124) OR _KEYDOWN(92) THEN rVal = 124
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "<" THEN
    IF _KEYDOWN(60) OR _KEYDOWN(44) THEN rVal = 60
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = ">" THEN
    IF _KEYDOWN(62) OR _KEYDOWN(46) THEN rVal = 62
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "'" THEN
    IF _KEYDOWN(34) OR _KEYDOWN(39) THEN rVal = 34
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "/" THEN
    IF _KEYDOWN(63) OR _KEYDOWN(47) THEN rVal = 63
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "ENT" THEN ' ENTER key
    IF _KEYDOWN(13) THEN rVal = 13
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "PGUP" THEN
    IF _KEYDOWN(18688) THEN rVal = 18688
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "PGDN" THEN
    IF _KEYDOWN(20736) THEN rVal = 20736
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "HOME" THEN
    IF _KEYDOWN(18176) THEN rVal = 18176
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "END" THEN
    IF _KEYDOWN(20224) THEN rVal = 20224
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "[" THEN ' Key [ or {
    IF _KEYDOWN(123) OR _KEYDOWN(91) THEN rVal = 123
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF wStr$ = "]" THEN ' Key ] or }
    IF _KEYDOWN(125) OR _KEYDOWN(93) THEN rVal = 125
    keyCheck = rVal
    EXIT FUNCTION
  END IF

  IF rVal <> 0 THEN lastKeyPress = rVal
  keyCheck = rVal ' Always returns uppercase equivalent

END FUNCTION ' keyCheck

''''''''''''''''''''''''
SUB limitSpeed

  ' Only throttle program execution speed to 60 FPS if there is no compilation active
  IF compileState = COMP_IDLE THEN
    _LIMIT 60
  END IF

END SUB ' limitSpeed

''''''''''''''''''''''''
FUNCTION mouseClickedInBox (wStartX, wStartY, wSizeX, wSizeY)

  tempRet = 0

  IF mouse.Released1 THEN
    IF mouseWithinBoxBounds(wStartX, wStartY, wSizeX, wSizeY) THEN
      IF mouseDownWithinBoxBounds(wStartX, wStartY, wSizeX, wSizeY) THEN
        tempRet = 1
      END IF
    END IF
  END IF

  mouseClickedInBox = tempRet

END FUNCTION ' mouseClickedInBox

''''''''''''''''''''''''
FUNCTION mouseDownWithinBoxBounds (wStartX, wStartY, wSizeX, wSizeY)

  toRet = 0

  IF mouse.DownPosX >= wStartX AND mouse.DownPosX <= (wStartX + wSizeX - 1) AND mouse.DownPosY >= wStartY AND mouse.DownPosY <= (wStartY + wSizeY - 1) THEN
    toRet = 1
  END IF

  mouseDownWithinBoxBounds = toRet

END FUNCTION ' mouseDownWithinBoxBounds
''''''''''''''''''''''''
FUNCTION mouseDown2WithinBoxBounds (wStartX, wStartY, wSizeX, wSizeY)

  toRet = 0

  IF mouse.DownPosX2 >= wStartX AND mouse.DownPosX2 <= (wStartX + wSizeX - 1) AND mouse.DownPosY2 >= wStartY AND mouse.DownPosY2 <= (wStartY + wSizeY - 1) THEN
    toRet = 1
  END IF

  mouseDown2WithinBoxBounds = toRet

END FUNCTION ' mouseDown2WithinBoxBounds

''''''''''''''''''''''''
SUB mouseReadInput

  mouse.Released1 = 0
  mouse.Released2 = 0
  mouse.Clicked1 = 0
  mouse.Clicked2 = 0
  mouse.Wheel = 0

  DO WHILE _MOUSEINPUT

    mPosX = _MOUSEX: mPosY = _MOUSEY
    mouse.PosX = mPosX: mouse.PosY = mPosY
    mouse.Wheel = mouse.Wheel + _MOUSEWHEEL

    pollMouse1Button = _MOUSEBUTTON(1)
    IF pollMouse1Button <> mouse.Button1Down THEN
      IF pollMouse1Button THEN
        mouse.Clicked1 = 1
        mouse.DownPosX = mouse.PosX
        mouse.DownPosY = mouse.PosY
      ELSE
        mouse.Released1 = 1
      END IF
      mouse.Button1Down = pollMouse1Button
    END IF

    pollMouse2Button = _MOUSEBUTTON(2)
    IF pollMouse2Button <> mouse.Button2Down THEN
      IF pollMouse2Button THEN
        mouse.Clicked2 = 1
        mouse.DownPosX2 = mouse.PosX
        mouse.DownPosY2 = mouse.PosY
      ELSE
        mouse.Released2 = 1
      END IF
      mouse.Button2Down = pollMouse2Button
      EXIT SUB
    END IF

  LOOP

END SUB ' mouseReadInput

''''''''''''''''''''''''
FUNCTION mouseWithinBoxBounds (wStartX, wStartY, wSizeX, wSizeY)

  ' We use a slightly more forgiving check to handle edge-of-screen jitter
  ' wSizeX and wSizeY are the dimensions, so the right edge is wStartX + wSizeX - 1

  toRet = 0

  ' Use <= to ensure the final pixel is included
  ' We also add a small safety margin if the click is at the absolute screen edge
  IF mouse.PosX >= wStartX AND mouse.PosX <= (wStartX + wSizeX - 1) AND mouse.PosY >= wStartY AND mouse.PosY <= (wStartY + wSizeY - 1) THEN
    toRet = 1
  END IF

  mouseWithinBoxBounds = toRet

END FUNCTION ' mouseWithinBoxBounds

''''''''''''''''''''''''
SUB opAddRsp32 (wVal AS LONG)

  ' Using opALU instead of this function will output 4 bytes instead of 7 bytes since opALU compresses values under 128

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opAddRsp32"
  END IF

  emitByteCode &H48 ' REX.W
  emitByteCode &H81 ' ALU format 81
  emitByteCode &HC4 ' ModRM for ADD RSP
  emitBytes32 wVal

  stack.currentStackOffset = stack.currentStackOffset - wVal
  ff = updateStackAlignment

END SUB ' opAddRsp32

''''''''''''''''''''''''
FUNCTION opALU (aluOpCode, destType, destInfo, srcType, srcInfo, opSizeOrFlag)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opALU"
  END IF

  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM disp32 AS LONG
  DIM tempRet AS LONG
  DIM useImm8 AS LONG

  DIM opBase03 AS LONG
  DIM opBase01 AS LONG
  DIM opBase81 AS LONG
  DIM opBase83 AS LONG

  tempRet = 0 ' Default return value, 0 means no patch position

  ' RSP (4) is permitted because opALU natively handles SUB RSP and ADD RSP for stack frame allocation
  ' RBP (5) is prohibited to prevent accidental modifications to the stable base frame pointer anchoring local variables
  IF destType = OP_TYPE_REG THEN
    IF destInfo < 0 OR destInfo > 15 OR destInfo = 5 THEN
      ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(destInfo)) + ") in opALU. RBP (5) is protected."
    END IF
  END IF

  IF opSizeOrFlag = MODE_RIP THEN
    srcReg = srcInfo
    rex = calcRex(64, srcReg, REG_NONE, REG_NONE)
    IF rex > 0 THEN emitByteCode rex
    emitByteCode &H01 + (aluOpCode * 8)
    modRM = ((srcReg AND 7) * 8) + 5
    emitByteCode modRM
    tempRet = stream.emitPos
    emitBytes32 0
    opALU = tempRet
    EXIT FUNCTION
  END IF

  ' Set dynamic opcode bases based on operation bit size
  opBase03 = &H03
  opBase01 = &H01
  opBase81 = &H81
  opBase83 = &H83

  IF opSizeOrFlag = 8 THEN
    opBase03 = &H02
    opBase01 = &H00
    opBase81 = &H80
    opBase83 = &H80 ' 8-bit immediate operations don't need the sign-extended 83 base
  END IF

  SELECT CASE destType

    CASE OP_TYPE_ACC ' Explicit Accumulator-to-Immediate operations
      ' Requires srcType to be OP_TYPE_IMM
      rex = calcRex(opSizeOrFlag, REG_NONE, REG_NONE, REG_NONE)
      IF opSizeOrFlag = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF opSizeOrFlag = 8 THEN
        emitByteCode (aluOpCode * 8) + &H04
        emitByteCode (srcInfo AND 255)
      ELSE
        emitByteCode (aluOpCode * 8) + &H05
        IF opSizeOrFlag = 16 THEN
          emitByteCode (srcInfo AND 255)
          emitByteCode ((srcInfo \ 256) AND 255)
        ELSE
          emitBytes32 srcInfo
        END IF
      END IF

    CASE OP_TYPE_REG
      destReg = destInfo

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Register
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, destReg, srcReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_REG_ALT
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, destReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase01 + (aluOpCode * 8)
          modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_IMM ' Immediate-to-Register
          rex = calcRex(opSizeOrFlag, 0, destReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN
            emitByteCode opBase83
            modRM = &HC0 + (aluOpCode * 8) + (destReg AND 7)
            emitByteCode modRM
            emitByteCode (srcInfo AND 255)
          ELSE
            emitByteCode opBase81
            modRM = &HC0 + (aluOpCode * 8) + (destReg AND 7)
            emitByteCode modRM
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

        CASE OP_TYPE_MEM_RIP ' Memory-to-Register (RIP-relative)
          rex = calcRex(opSizeOrFlag, destReg, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          modRM = ((destReg AND 7) * 8) + 5
          emitByteCode modRM
          tempRet = stream.emitPos
          emitBytes32 0

        CASE OP_TYPE_MEM_RSP ' Memory-to-Register (RSP-relative)
          rex = calcRex(opSizeOrFlag, destReg, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          IF srcInfo >= -128 AND srcInfo <= 127 THEN
            emitMemoryOperand destReg, 4, 8, srcInfo
          ELSE
            emitMemoryOperand destReg, 4, 32, srcInfo
          END IF

        CASE OP_TYPE_MEM_RBP ' Memory-to-Register (RBP-relative)
          rex = calcRex(opSizeOrFlag, destReg, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          emitMemoryOperand destReg, 5, 32, srcInfo

        CASE OP_TYPE_MEM_REG ' Memory-to-Register (Register-Indirect, no displacement)
          baseReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          emitMemoryOperand destReg, baseReg, 0, 0

        CASE OP_TYPE_MEM_REG_DISP8 ' Memory-to-Register (Register-Indirect with 8-bit disp)
          baseReg = srcInfo AND 15
          disp8 = ((srcInfo - baseReg) \ 256) AND 255
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          emitMemoryOperand destReg, baseReg, 8, disp8

        CASE OP_TYPE_MEM_REG_DISP32 ' Memory-to-Register (Register-Indirect with 32-bit disp)
          baseReg = srcInfo AND 15
          disp32 = (srcInfo - baseReg) \ 256
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase03 + (aluOpCode * 8)
          emitMemoryOperand destReg, baseReg, 32, disp32

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RIP ' Register-to-Memory (RIP-relative)
      srcReg = srcInfo
      rex = calcRex(opSizeOrFlag, srcReg, REG_NONE, REG_NONE)
      IF opSizeOrFlag = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex
      emitByteCode opBase01 + (aluOpCode * 8)
      modRM = ((srcReg AND 7) * 8) + 5
      emitByteCode modRM
      tempRet = stream.emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Memory (RSP-relative)
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase01 + (aluOpCode * 8)
          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitMemoryOperand srcReg, 4, 8, destInfo
          ELSE
            emitMemoryOperand srcReg, 4, 32, destInfo
          END IF

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RSP-relative)
          rex = calcRex(opSizeOrFlag, 0, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN emitByteCode opBase83 ELSE emitByteCode opBase81
          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitMemoryOperand aluOpCode, 4, 8, destInfo
          ELSE
            emitMemoryOperand aluOpCode, 4, 32, destInfo
          END IF

          IF useImm8 = 1 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RBP

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Memory (RBP-relative)
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase01 + (aluOpCode * 8)
          emitMemoryOperand srcReg, 5, 32, destInfo

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RBP-relative)
          rex = calcRex(opSizeOrFlag, 0, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN emitByteCode opBase83 ELSE emitByteCode opBase81
          emitMemoryOperand aluOpCode, 5, 32, destInfo

          IF useImm8 = 1 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG
      baseReg = destInfo AND 15

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase01 + (aluOpCode * 8)
          emitMemoryOperand srcReg, baseReg, 0, 0

        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN emitByteCode opBase83 ELSE emitByteCode opBase81
          emitMemoryOperand aluOpCode, baseReg, 0, 0

          IF useImm8 = 1 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = destInfo AND 15
      disp8 = ((destInfo - baseReg) \ 256) AND 255

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase01 + (aluOpCode * 8)
          emitMemoryOperand srcReg, baseReg, 8, disp8

        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN emitByteCode opBase83 ELSE emitByteCode opBase81
          emitMemoryOperand aluOpCode, baseReg, 8, disp8

          IF useImm8 = 1 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG_DISP32
      baseReg = destInfo AND 15
      disp32 = (destInfo - baseReg) \ 256

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase01 + (aluOpCode * 8)
          emitMemoryOperand srcReg, baseReg, 32, disp32

        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN emitByteCode opBase83 ELSE emitByteCode opBase81
          emitMemoryOperand aluOpCode, baseReg, 32, disp32

          IF useImm8 = 1 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

  END SELECT ' destType

  opALU = tempRet

END FUNCTION ' opALU

''''''''''''''''''''''''
FUNCTION opALU_SIB (aluOpCode, destIsMem AS LONG, valType AS LONG, valInfo AS _INTEGER64, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG, opSize AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opALU_SIB"
  END IF

  DIM rex AS _UNSIGNED _BYTE
  DIM tempRet AS LONG
  DIM regField AS LONG
  DIM useImm8 AS LONG

  tempRet = 0
  rex = 0

  ' RSP (4) and RBP (5) are protected as destination targets to prevent complex scaled calculations from corrupting the stack or base frame pointers

  IF valType = OP_TYPE_REG AND destIsMem = 0 THEN
    IF valInfo < 0 OR valInfo > 15 OR valInfo = 4 OR valInfo = 5 THEN
      ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(valInfo)) + ") in opALU_SIB. RSP (4) and RBP (5) are protected."
    END IF
  END IF

  IF opSize = 64 THEN rex = rex OR &H08
  IF indexReg >= 8 THEN rex = rex OR &H02
  IF baseReg >= 8 THEN rex = rex OR &H01

  IF valType = OP_TYPE_REG THEN
    regField = valInfo
    IF regField >= 8 THEN rex = rex OR &H04

    IF opSize = 8 AND regField >= 4 AND regField <= 7 THEN
      rex = rex OR &H40
    END IF

    IF opSize = 16 THEN emitByteCode &H66
    IF rex > 0 THEN emitByteCode &H40 OR rex

    IF opSize = 8 THEN
      IF destIsMem = 1 THEN emitByteCode &H00 + (aluOpCode * 8) ELSE emitByteCode &H02 + (aluOpCode * 8)
    ELSE
      IF destIsMem = 1 THEN emitByteCode &H01 + (aluOpCode * 8) ELSE emitByteCode &H03 + (aluOpCode * 8)
    END IF
  ELSE
    regField = aluOpCode

    IF opSize = 16 THEN emitByteCode &H66
    IF rex > 0 THEN emitByteCode &H40 OR rex

    useImm8 = 0
    IF opSize = 8 THEN
      useImm8 = 1
    ELSE
      IF valInfo >= -128 AND valInfo <= 127 THEN
        useImm8 = 1
      END IF
    END IF

    IF opSize = 8 THEN
      emitByteCode &H80
    ELSE
      IF useImm8 = 1 THEN emitByteCode &H83 ELSE emitByteCode &H81
    END IF
  END IF

  opHelperEmitSIBoperand regField, baseReg, indexReg, scaleVal, dispVal

  IF valType = OP_TYPE_IMM THEN
    IF useImm8 = 1 THEN
      emitByteCode valInfo AND 255
    ELSE
      IF opSize = 16 THEN
        emitByteCode valInfo AND 255
        emitByteCode (valInfo \ 256) AND 255
      ELSE
        emitBytes32 valInfo
      END IF
    END IF
  END IF

  opALU_SIB = tempRet

END FUNCTION ' opALU_SIB

''''''''''''''''''''''''
FUNCTION opCall (wInfo, wMode)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL: UNAUTHORIZED OP CALL IN opCall"
  END IF

  DIM tempRet AS LONG
  tempRet = 0

  IF STACKSAFETYCHECK = 1 THEN

    IF updateStackAlignment = 0 THEN
      err1$ = "FATAL: Unaligned call offset:" + LTRIM$(STR$(stack.currentStackOffset)) + " bytes"

      ' Safely append the line number and subroutine name to the error string so the user knows exactly where it failed
      IF currentLineNumber > 0 AND currentLineNumber <= EDITOR_LINE_MAX THEN
        err1$ = err1$ + " Line: " + LTRIM$(STR$(currentLineNumber))
      END IF
      IF currentSubName$ <> "" THEN
        err1$ = err1$ + " in SUB: " + currentSubName$
      END IF

      ' Grab the actual text of the line from the editor array to print to the screen for visual debugging
      err2$ = ""
      IF currentLineNumber > 0 AND currentLineNumber <= EDITOR_LINE_MAX THEN
        IF compileText$(currentLineNumber) <> "" THEN
          err2$ = "[" + LTRIM$(RTRIM$(compileText$(currentLineNumber))) + "]"
        END IF
      END IF

      ' Append the internal caller metadata (IAT Index or Sub Index) to assist the compiler developer
      err2$ = err2$ + " (wInfo: " + LTRIM$(STR$(wInfo)) + ", wMode: " + LTRIM$(STR$(wMode)) + ")"

      ' Terminate compiler immediately to prevent generating a corrupted executable
      ESCAPETEXT2 err1$, err2$
    END IF
  END IF

  IF wMode = CALLMODE_IAT THEN
    ' Emit 0xFF 0x15, which is the x64 opcode for an absolute indirect call (CALL QWORD PTR [RIP+disp])
    emitByteCode &HFF
    emitByteCode &H15

    ' Queue the offset in the IAT patch list so prepareBinary can link it to the OS DLL table later
    addPatch PATCH_IAT, stream.emitPos, wInfo
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      opCall = 0
      EXIT FUNCTION
    END IF

    ' Emit 4 null bytes as a placeholder for the 32-bit displacement value
    tempRet = stream.emitPos
    emitBytes32 0

  ELSE
    ' Internal subroutine / runtime helper emission (relative 32-bit Call)
    IF wMode = CALLMODE_REL32 THEN
      ' Emit 0xE8, which is the x64 opcode for a relative call (CALL rel32)
      emitByteCode &HE8

      ' Emit 4 null bytes as a placeholder for the displacement value
      tempRet = stream.emitPos
      emitBytes32 0
    END IF
  END IF

  ' Return the stream offset where the 4-byte displacement needs to be patched
  opCall = tempRet

END FUNCTION ' opCall

''''''''''''''''''''''''
SUB opDecReg (wReg, opSize)

  ' Only supports registers, unlike the opUnary version, but generates less boilerplate

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opDecReg"
  END IF

  DIM rex AS _UNSIGNED _BYTE

  IF wReg < 0 OR wReg > 15 OR wReg = 4 OR wReg = 5 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(wReg)) + ") in opDecReg. RSP (4) and RBP (5) are protected."
  END IF

  rex = 0

  IF opSize = 64 THEN rex = rex OR &H08
  IF wReg >= 8 THEN rex = rex OR &H01

  ' 8-bit SPL, BPL, SIL, DIL need empty REX prefix to not compile as AH, CH, DH, BH
  IF opSize = 8 AND wReg >= 4 AND wReg <= 7 THEN
    rex = rex OR &H40
  END IF

  IF opSize = 16 THEN emitByteCode &H66
  IF rex > 0 THEN emitByteCode &H40 OR rex

  IF opSize = 8 THEN
    emitByteCode &HFE
  ELSE
    emitByteCode &HFF
  END IF

  emitByteCode &HC8 + (wReg AND 7)

END SUB ' opDecReg

''''''''''''''''''''''''
SUB opExtend (wExtendType)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opExtend"
  END IF

  SELECT CASE wExtendType

    CASE EXTEND_CWD
      emitByteCode &H66
      emitByteCode &H99

    CASE EXTEND_CDQ
      emitByteCode &H99

    CASE EXTEND_CQO
      emitByteCode &H48
      emitByteCode &H99

  END SELECT ' wExtendType

END SUB ' opExtend

''''''''''''''''''''''''
SUB opFlag (wFlagType)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opFlag"
  END IF

  SELECT CASE wFlagType

    CASE FLAG_CLD
      emitByteCode &HFC

    CASE FLAG_STD
      emitByteCode &HFD

    CASE FLAG_CLI
      emitByteCode &HFA

    CASE FLAG_STI
      emitByteCode &HFB

    CASE FLAG_CLC
      emitByteCode &HF8

    CASE FLAG_STC
      emitByteCode &HF9

    CASE FLAG_CMC
      emitByteCode &HF5

  END SELECT ' wFlagType

END SUB ' opFlag

''''''''''''''''''''''''
SUB opHelperEmitSIBoperand (regField AS LONG, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opHelperEmitSIBoperand"
  END IF

  DIM modBits AS LONG
  DIM scaleBits AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM sibByte AS _UNSIGNED _BYTE

  IF dispVal = 0 AND (baseReg AND 7) <> 5 THEN
    modBits = 0
  ELSE
    IF dispVal >= -128 AND dispVal <= 127 THEN
      modBits = 1
    ELSE
      modBits = 2
    END IF
  END IF

  modRM = (modBits * 64) + ((regField AND 7) * 8) + 4
  emitByteCode modRM

  SELECT CASE scaleVal

    CASE 2: scaleBits = 1
    CASE 4: scaleBits = 2
    CASE 8: scaleBits = 3
    CASE ELSE: scaleBits = 0

  END SELECT ' scaleVal

  sibByte = (scaleBits * 64) + ((indexReg AND 7) * 8) + (baseReg AND 7)
  emitByteCode sibByte

  IF modBits = 1 THEN
    emitByteCode dispVal AND 255
  ELSE
    IF modBits = 2 THEN
      emitBytes32 dispVal
    END IF
  END IF

END SUB ' opHelperEmitSIBoperand

''''''''''''''''''''''''
FUNCTION opImul (destReg AS LONG, srcType AS LONG, srcInfo AS _INTEGER64, immVal AS _INTEGER64, opMode AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opImul"
  END IF

  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM disp32 AS LONG
  DIM tempRet AS LONG
  DIM useImm8 AS LONG
  DIM opSize AS LONG
  DIM isImmMode AS LONG

  checkRegisterBounds destReg, "opImul"

  tempRet = 0
  opSize = 32
  isImmMode = 0

  IF opMode = MODE_IMUL64_REG OR opMode = MODE_IMUL64_IMM OR opMode = MODE_IMUL64_IMM32 THEN opSize = 64
  IF opMode = MODE_IMUL32_IMM OR opMode = MODE_IMUL64_IMM OR opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN isImmMode = 1

  SELECT CASE srcType

    CASE OP_TYPE_REG
      srcReg = srcInfo
      rex = calcRex(opSize, destReg, srcReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex

      IF isImmMode = 1 THEN
        IF opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN
          useImm8 = 0
        ELSE
          IF immVal >= -128 AND immVal <= 127 THEN useImm8 = 1 ELSE useImm8 = 0
        END IF
        IF useImm8 = 1 THEN emitByteCode &H6B ELSE emitByteCode &H69
      ELSE
        emitByteCode &H0F
        emitByteCode &HAF
      END IF

      modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
      emitByteCode modRM

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_RIP
      rex = calcRex(opSize, destReg, REG_NONE, REG_NONE)
      IF rex > 0 THEN emitByteCode rex

      IF isImmMode = 1 THEN
        IF opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN
          useImm8 = 0
        ELSE
          IF immVal >= -128 AND immVal <= 127 THEN useImm8 = 1 ELSE useImm8 = 0
        END IF
        IF useImm8 = 1 THEN emitByteCode &H6B ELSE emitByteCode &H69
      ELSE
        emitByteCode &H0F
        emitByteCode &HAF
      END IF

      modRM = ((destReg AND 7) * 8) + 5
      emitByteCode modRM
      tempRet = stream.emitPos
      emitBytes32 0

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_RSP
      rex = calcRex(opSize, destReg, 4, REG_NONE)
      IF rex > 0 THEN emitByteCode rex

      IF isImmMode = 1 THEN
        IF opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN
          useImm8 = 0
        ELSE
          IF immVal >= -128 AND immVal <= 127 THEN useImm8 = 1 ELSE useImm8 = 0
        END IF
        IF useImm8 = 1 THEN emitByteCode &H6B ELSE emitByteCode &H69
      ELSE
        emitByteCode &H0F
        emitByteCode &HAF
      END IF

      IF srcInfo >= -128 AND srcInfo <= 127 THEN
        emitMemoryOperand destReg, 4, 8, srcInfo
      ELSE
        emitMemoryOperand destReg, 4, 32, srcInfo
      END IF

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_REG
      baseReg = srcInfo AND 15
      rex = calcRex(opSize, destReg, baseReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex

      IF isImmMode = 1 THEN
        IF opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN
          useImm8 = 0
        ELSE
          IF immVal >= -128 AND immVal <= 127 THEN useImm8 = 1 ELSE useImm8 = 0
        END IF
        IF useImm8 = 1 THEN emitByteCode &H6B ELSE emitByteCode &H69
      ELSE
        emitByteCode &H0F
        emitByteCode &HAF
      END IF

      emitMemoryOperand destReg, baseReg, 0, 0

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = srcInfo AND 15
      disp8 = ((srcInfo - baseReg) \ 256) AND 255
      rex = calcRex(opSize, destReg, baseReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex

      IF isImmMode = 1 THEN
        IF opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN
          useImm8 = 0
        ELSE
          IF immVal >= -128 AND immVal <= 127 THEN useImm8 = 1 ELSE useImm8 = 0
        END IF
        IF useImm8 = 1 THEN emitByteCode &H6B ELSE emitByteCode &H69
      ELSE
        emitByteCode &H0F
        emitByteCode &HAF
      END IF

      emitMemoryOperand destReg, baseReg, 8, disp8

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_REG_DISP32
      baseReg = srcInfo AND 15
      disp32 = (srcInfo - baseReg) \ 256
      rex = calcRex(opSize, destReg, baseReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex

      IF isImmMode = 1 THEN
        IF opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN
          useImm8 = 0
        ELSE
          IF immVal >= -128 AND immVal <= 127 THEN useImm8 = 1 ELSE useImm8 = 0
        END IF
        IF useImm8 = 1 THEN emitByteCode &H6B ELSE emitByteCode &H69
      ELSE
        emitByteCode &H0F
        emitByteCode &HAF
      END IF

      emitMemoryOperand destReg, baseReg, 32, disp32

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

  END SELECT ' srcType

  opImul = tempRet

END FUNCTION ' opImul

''''''''''''''''''''''''
SUB opIncReg (wReg, opSize)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opIncReg"
  END IF

  ' Only supports registers, unlike the opUnary version, but generates less boilerplate

  DIM rex AS _UNSIGNED _BYTE

  IF wReg < 0 OR wReg > 15 OR wReg = 4 OR wReg = 5 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(wReg)) + ") in opIncReg. RSP (4) and RBP (5) are protected."
  END IF

  rex = 0

  IF opSize = 64 THEN rex = rex OR &H08
  IF wReg >= 8 THEN rex = rex OR &H01

  ' 8-bit SPL, BPL, SIL, DIL need empty REX prefix to not compile as AH, CH, DH, BH
  IF opSize = 8 AND wReg >= 4 AND wReg <= 7 THEN
    rex = rex OR &H40
  END IF

  IF opSize = 16 THEN emitByteCode &H66
  IF rex > 0 THEN emitByteCode &H40 OR rex

  IF opSize = 8 THEN
    emitByteCode &HFE
  ELSE
    emitByteCode &HFF
  END IF

  emitByteCode &HC0 + (wReg AND 7)

END SUB ' opIncReg

''''''''''''''''''''''''
FUNCTION opJcc (condCode, wMode, wTarget, wJumpType)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opJcc"
  END IF

  DIM tempRet AS LONG

  tempRet = 0

  IF wJumpType = JCC_TYPE_SHORT THEN
    IF condCode = JCC_JMP THEN
      emitByteCode &HEB
    ELSE
      emitByteCode &H70 + condCode
    END IF

    IF wMode = JCC_MODE_FORWARD THEN
      tempRet = stream.emitPos
      emitByteCode 0
    ELSE
      emitByteCode (wTarget - (stream.emitPos + 1)) AND 255
    END IF
  ELSE
    IF condCode = JCC_JMP THEN
      emitByteCode &HE9
    ELSE
      emitByteCode &H0F
      emitByteCode &H80 + condCode
    END IF

    IF wMode = JCC_MODE_FORWARD THEN
      ' We must capture the exact placement of the 4 displacement bytes.
      ' Because prepareBinary calculates offsets via (pOffEmit + 4) to find the instruction
      ' endpoint, we must consistently deliver the exact byte address immediately prior to the payload.
      tempRet = stream.emitPos
      emitBytes32 0
    ELSE
      emitBytes32 wTarget - (stream.emitPos + 4)
    END IF
  END IF

  opJcc = tempRet

END FUNCTION ' opJcc

''''''''''''''''''''''''
FUNCTION opLea (destType, destReg AS LONG, srcType, srcInfo AS _INTEGER64, opSizeOrFlag)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opLea"
  END IF

  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM disp32 AS LONG
  DIM tempRet AS LONG

  tempRet = 0

  IF destType <> OP_TYPE_REG THEN
    opLea = tempRet
    EXIT FUNCTION
  END IF

  checkRegisterBounds destReg, "opLea"

  SELECT CASE srcType

    CASE OP_TYPE_MEM_RIP
      rex = calcRex(opSizeOrFlag, destReg, REG_NONE, REG_NONE)
      IF rex > 0 THEN emitByteCode rex
      emitByteCode &H8D
      modRM = ((destReg AND 7) * 8) + 5
      emitByteCode modRM
      tempRet = stream.emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      rex = calcRex(opSizeOrFlag, destReg, 4, REG_NONE)
      IF rex > 0 THEN emitByteCode rex
      emitByteCode &H8D
      IF srcInfo >= -128 AND srcInfo <= 127 THEN
        emitMemoryOperand destReg, 4, 8, srcInfo
      ELSE
        emitMemoryOperand destReg, 4, 32, srcInfo
      END IF

    CASE OP_TYPE_MEM_RBP
      rex = calcRex(opSizeOrFlag, destReg, 5, REG_NONE)
      IF rex > 0 THEN emitByteCode rex
      emitByteCode &H8D
      emitMemoryOperand destReg, 5, 32, srcInfo

    CASE OP_TYPE_MEM_REG
      baseReg = srcInfo AND 15
      rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex
      emitByteCode &H8D
      emitMemoryOperand destReg, baseReg, 0, 0

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = srcInfo AND 15
      disp8 = ((srcInfo - baseReg) \ 256) AND 255
      rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex
      emitByteCode &H8D
      emitMemoryOperand destReg, baseReg, 8, disp8

    CASE OP_TYPE_MEM_REG_DISP32
      baseReg = srcInfo AND 15
      disp32 = (srcInfo - baseReg) \ 256
      rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
      IF rex > 0 THEN emitByteCode rex
      emitByteCode &H8D
      emitMemoryOperand destReg, baseReg, 32, disp32

  END SELECT ' srcType

  opLea = tempRet

END FUNCTION ' opLea

''''''''''''''''''''''''
FUNCTION opLea_SIB (destReg AS LONG, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG, opSize AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opLea_SIB"
  END IF

  DIM rex AS _UNSIGNED _BYTE
  DIM tempRet AS LONG

  checkRegisterBounds destReg, "opLea_SIB"

  tempRet = 0
  rex = 0

  IF opSize = 64 THEN rex = rex OR &H08
  IF destReg >= 8 THEN rex = rex OR &H04
  IF indexReg >= 8 THEN rex = rex OR &H02
  IF baseReg >= 8 THEN rex = rex OR &H01

  IF rex > 0 THEN emitByteCode &H40 OR rex

  emitByteCode &H8D

  opHelperEmitSIBoperand destReg, baseReg, indexReg, scaleVal, dispVal

  opLea_SIB = tempRet

END FUNCTION ' opLea_SIB

''''''''''''''''''''''''
FUNCTION opMov (destType, destInfo AS LONG, srcType, srcInfo AS _INTEGER64, opSizeOrFlag)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opMov"
  END IF

  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM uVal64 AS _UNSIGNED _INTEGER64
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM disp32 AS LONG
  DIM is8bitSource AS LONG
  DIM is0FPrefix AS LONG
  DIM opCodeByte AS _UNSIGNED _BYTE
  DIM destOpSize AS LONG
  DIM tempRet AS LONG

  tempRet = 0 ' Default return value, 0 means no patch position

  IF destType = OP_TYPE_REG THEN
    ' RSP (4) is blocked because stack pointer modifications must go through explicit stack tracking subroutines
    ' RBP (5) is permitted because opMov natively handles MOV RBP, RSP for stack frame setup
    IF destInfo < 0 OR destInfo > 15 OR destInfo = 4 THEN
      ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(destInfo)) + ") in opMov. RSP (4) is protected."
    END IF
  END IF

  SELECT CASE opSizeOrFlag

    CASE MODE_MOVZX32_8, MODE_MOVZX32_16, MODE_MOVZX64_8, MODE_MOVZX64_16, MODE_MOVSX32_8, MODE_MOVSX32_16, MODE_MOVSX64_8, MODE_MOVSX64_16, MODE_MOVSXD
      ' Handles movzx, movsx, movsxd
      IF destType <> OP_TYPE_REG THEN
        opMov = tempRet
        EXIT FUNCTION
      END IF

      destReg = destInfo
      is8bitSource = 0
      is0FPrefix = 1
      destOpSize = 32

      IF opSizeOrFlag = MODE_MOVZX64_8 OR opSizeOrFlag = MODE_MOVZX64_16 OR opSizeOrFlag = MODE_MOVSX64_8 OR opSizeOrFlag = MODE_MOVSX64_16 OR opSizeOrFlag = MODE_MOVSXD THEN
        destOpSize = 64
      END IF

      IF opSizeOrFlag = MODE_MOVZX32_8 OR opSizeOrFlag = MODE_MOVZX64_8 OR opSizeOrFlag = MODE_MOVSX32_8 OR opSizeOrFlag = MODE_MOVSX64_8 THEN
        is8bitSource = 1
      END IF

      IF opSizeOrFlag = MODE_MOVSXD THEN
        is0FPrefix = 0
        opCodeByte = &H63
      ELSE

        SELECT CASE opSizeOrFlag

          CASE MODE_MOVZX32_8, MODE_MOVZX64_8
            opCodeByte = &HB6
          CASE MODE_MOVZX32_16, MODE_MOVZX64_16
            opCodeByte = &HB7
          CASE MODE_MOVSX32_8, MODE_MOVSX64_8
            opCodeByte = &HBE
          CASE MODE_MOVSX32_16, MODE_MOVSX64_16
            opCodeByte = &HBF

        END SELECT ' opSizeOrFlag

      END IF

      SELECT CASE srcType

        CASE OP_TYPE_REG ' MOVZX/MOVSX r_dest, r_src
          srcReg = srcInfo
          rex = calcRex(destOpSize, destReg, srcReg, REG_NONE)
          IF is8bitSource = 1 THEN
            IF srcReg >= 4 AND srcReg <= 7 THEN rex = rex OR &H40
          END IF

          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_MEM_RIP ' MOVZX/MOVSX r_dest, [rip+disp32]
          rex = calcRex(destOpSize, destReg, REG_NONE, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          modRM = ((destReg AND 7) * 8) + 5
          emitByteCode modRM
          tempRet = stream.emitPos
          emitBytes32 0

        CASE OP_TYPE_MEM_RSP ' MOVZX/MOVSX r_dest, [rsp+disp]
          rex = calcRex(destOpSize, destReg, 4, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          IF srcInfo >= -128 AND srcInfo <= 127 THEN
            emitMemoryOperand destReg, 4, 8, srcInfo
          ELSE
            emitMemoryOperand destReg, 4, 32, srcInfo
          END IF

        CASE OP_TYPE_MEM_RBP ' MOVZX/MOVSX r_dest, [rbp+disp32]
          rex = calcRex(destOpSize, destReg, 5, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          emitMemoryOperand destReg, 5, 32, srcInfo

        CASE OP_TYPE_MEM_REG ' MOVZX/MOVSX r_dest, [base_reg]
          baseReg = srcInfo AND 15
          rex = calcRex(destOpSize, destReg, baseReg, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          emitMemoryOperand destReg, baseReg, 0, 0

        CASE OP_TYPE_MEM_REG_DISP8 ' MOVZX/MOVSX r_dest, [base_reg+disp8]
          baseReg = srcInfo AND 15
          disp8 = ((srcInfo - baseReg) \ 256) AND 255
          rex = calcRex(destOpSize, destReg, baseReg, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          emitMemoryOperand destReg, baseReg, 8, disp8

        CASE OP_TYPE_MEM_REG_DISP32 ' MOVZX/MOVSX r_dest, [base_reg+disp32]
          baseReg = srcInfo AND 15
          disp32 = (srcInfo - baseReg) \ 256
          rex = calcRex(destOpSize, destReg, baseReg, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          emitMemoryOperand destReg, baseReg, 32, disp32

        CASE OP_TYPE_MEM_GS_ABS32 ' MOVZX/MOVSX r_dest, gs:[abs32]
          emitByteCode &H65
          rex = calcRex(destOpSize, destReg, REG_NONE, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          modRM = ((destReg AND 7) * 8) + 4
          emitByteCode modRM
          emitByteCode &H25
          emitBytes32 srcInfo

        CASE OP_TYPE_MEM_GS_REG_DISP32 ' MOVZX/MOVSX r_dest, gs:[base_reg+disp32]
          baseReg = srcInfo AND 15
          disp32 = (srcInfo - baseReg) \ 256
          emitByteCode &H65
          rex = calcRex(destOpSize, destReg, baseReg, REG_NONE)
          IF rex > 0 THEN emitByteCode rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          emitMemoryOperand destReg, baseReg, 32, disp32

      END SELECT ' srcType

      opMov = tempRet
      EXIT FUNCTION ' Extension logic is complete, exit

  END SELECT ' opSizeOrFlag

  IF opSizeOrFlag = MODE_IMM64 THEN
    destReg = destInfo
    rex = calcRex(64, REG_NONE, destReg, REG_NONE)
    IF rex > 0 THEN emitByteCode rex
    emitByteCode &HB8 + (destReg AND 7)

    uVal64 = srcInfo
    FOR ii = 1 TO 8
      emitByteCode (uVal64 AND 255)
      uVal64 = uVal64 \ 256
    NEXT
    opMov = tempRet
    EXIT FUNCTION
  END IF

  IF opSizeOrFlag = MODE_RIP THEN
    srcReg = srcInfo
    rex = calcRex(64, srcReg, REG_NONE, REG_NONE)
    IF rex > 0 THEN emitByteCode rex
    emitByteCode &H89
    modRM = ((srcReg AND 7) * 8) + 5
    emitByteCode modRM
    tempRet = stream.emitPos
    emitBytes32 0
    opMov = tempRet
    EXIT FUNCTION
  END IF

  SELECT CASE destType

    CASE OP_TYPE_REG
      destReg = destInfo

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Register
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, destReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_REG_ALT
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, destReg, srcReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_IMM ' Immediate-to-Register
          IF opSizeOrFlag = 8 THEN
            rex = calcRex(8, REG_NONE, destReg, REG_NONE)
            IF rex > 0 THEN emitByteCode rex
            emitByteCode &HB0 + (destReg AND 7)
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 64 THEN
              uVal64 = srcInfo
              IF srcInfo >= -2147483648 AND srcInfo <= 2147483647 THEN
                rex = calcRex(64, 0, destReg, REG_NONE)
                IF rex > 0 THEN emitByteCode rex
                emitByteCode &HC7
                modRM = &HC0 + (destReg AND 7)
                emitByteCode modRM
                emitBytes32 srcInfo
              ELSE
                rex = calcRex(64, REG_NONE, destReg, REG_NONE)
                IF rex > 0 THEN emitByteCode rex
                emitByteCode &HB8 + (destReg AND 7)
                FOR ii = 1 TO 8
                  emitByteCode (uVal64 AND 255)
                  uVal64 = uVal64 \ 256
                NEXT
              END IF
            ELSE ' opSizeOrFlag = 32 or 16
              rex = calcRex(opSizeOrFlag, REG_NONE, destReg, REG_NONE)
              IF opSizeOrFlag = 16 THEN emitByteCode &H66
              IF rex > 0 THEN emitByteCode rex
              emitByteCode &HB8 + (destReg AND 7)
              IF opSizeOrFlag = 16 THEN
                emitByteCode (srcInfo AND 255)
                emitByteCode ((srcInfo \ 256) AND 255)
              ELSE
                emitBytes32 srcInfo
              END IF
            END IF
          END IF

        CASE OP_TYPE_MEM_RIP ' Memory-to-Register (RIP-relative)
          rex = calcRex(opSizeOrFlag, destReg, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          modRM = ((destReg AND 7) * 8) + 5
          emitByteCode modRM
          tempRet = stream.emitPos
          emitBytes32 0

        CASE OP_TYPE_MEM_RSP ' Memory-to-Register (RSP-relative)
          rex = calcRex(opSizeOrFlag, destReg, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          IF srcInfo >= -128 AND srcInfo <= 127 THEN
            emitMemoryOperand destReg, 4, 8, srcInfo
          ELSE
            emitMemoryOperand destReg, 4, 32, srcInfo
          END IF

        CASE OP_TYPE_MEM_RBP ' Memory-to-Register (RBP-relative)
          rex = calcRex(opSizeOrFlag, destReg, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          emitMemoryOperand destReg, 5, 32, srcInfo

        CASE OP_TYPE_MEM_REG ' Memory-to-Register (Register-Indirect, no displacement)
          baseReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          emitMemoryOperand destReg, baseReg, 0, 0

        CASE OP_TYPE_MEM_REG_DISP8 ' Memory-to-Register (Register-Indirect with 8-bit disp)
          baseReg = srcInfo AND 15
          disp8 = ((srcInfo - baseReg) \ 256) AND 255
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          emitMemoryOperand destReg, baseReg, 8, disp8

        CASE OP_TYPE_MEM_REG_DISP32 ' Memory-to-Register (Register-Indirect with 32-bit disp)
          baseReg = srcInfo AND 15
          disp32 = (srcInfo - baseReg) \ 256
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          emitMemoryOperand destReg, baseReg, 32, disp32

        CASE OP_TYPE_MEM_GS_ABS32 ' Memory-to-Register (GS Segment Absolute 32-bit)
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, destReg, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          modRM = ((destReg AND 7) * 8) + 4
          emitByteCode modRM
          emitByteCode &H25
          emitBytes32 srcInfo

        CASE OP_TYPE_MEM_GS_REG_DISP32 ' Memory-to-Register (GS Segment Register-Indirect 32-bit disp)
          baseReg = srcInfo AND 15
          disp32 = (srcInfo - baseReg) \ 256
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H8A ELSE emitByteCode &H8B
          emitMemoryOperand destReg, baseReg, 32, disp32

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RIP ' Register-to-Memory (RIP-relative)
      srcReg = srcInfo
      rex = calcRex(opSizeOrFlag, srcReg, REG_NONE, REG_NONE)
      IF opSizeOrFlag = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex
      IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
      modRM = ((srcReg AND 7) * 8) + 5
      emitByteCode modRM
      tempRet = stream.emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Memory (RSP-relative)
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitMemoryOperand srcReg, 4, 8, destInfo
          ELSE
            emitMemoryOperand srcReg, 4, 32, destInfo
          END IF

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RSP-relative)
          rex = calcRex(opSizeOrFlag, 0, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitMemoryOperand 0, 4, 8, destInfo
          ELSE
            emitMemoryOperand 0, 4, 32, destInfo
          END IF
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RBP

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Memory (RBP-relative)
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          emitMemoryOperand srcReg, 5, 32, destInfo

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RBP-relative)
          rex = calcRex(opSizeOrFlag, 0, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          emitMemoryOperand 0, 5, 32, destInfo
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG
      baseReg = destInfo AND 15

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          emitMemoryOperand srcReg, baseReg, 0, 0

        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          emitMemoryOperand 0, baseReg, 0, 0
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = destInfo AND 15
      disp8 = ((destInfo - baseReg) \ 256) AND 255

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          emitMemoryOperand srcReg, baseReg, 8, disp8

        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          emitMemoryOperand 0, baseReg, 8, disp8
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG_DISP32
      baseReg = destInfo AND 15
      disp32 = (destInfo - baseReg) \ 256

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          emitMemoryOperand srcReg, baseReg, 32, disp32

        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          emitMemoryOperand 0, baseReg, 32, disp32
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_GS_ABS32 ' Register/Immediate-to-Memory (GS Segment Absolute 32-bit)

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, srcReg, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          modRM = ((srcReg AND 7) * 8) + 4
          emitByteCode modRM
          emitByteCode &H25
          emitBytes32 destInfo

        CASE OP_TYPE_IMM
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, 0, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          modRM = 4
          emitByteCode modRM
          emitByteCode &H25
          emitBytes32 destInfo
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_GS_REG_DISP32 ' Register/Immediate-to-Memory (GS Segment Register-Indirect 32-bit disp)
      baseReg = destInfo AND 15
      disp32 = (destInfo - baseReg) \ 256

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          emitMemoryOperand srcReg, baseReg, 32, disp32

        CASE OP_TYPE_IMM
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          emitMemoryOperand 0, baseReg, 32, disp32
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

  END SELECT ' destType

  opMov = tempRet

END FUNCTION ' opMov

''''''''''''''''''''''''
FUNCTION opMov_SIB (destIsMem AS LONG, valType AS LONG, valInfo AS _INTEGER64, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG, opSize AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opMov_SIB"
  END IF

  DIM rex AS _UNSIGNED _BYTE
  DIM tempRet AS LONG
  DIM regField AS LONG

  checkRegisterBounds baseReg, "opMov_SIB"

  tempRet = 0
  rex = 0

  IF opSize = 64 THEN rex = rex OR &H08
  IF indexReg >= 8 THEN rex = rex OR &H02
  IF baseReg >= 8 THEN rex = rex OR &H01

  IF valType = OP_TYPE_REG THEN
    regField = valInfo
    IF regField >= 8 THEN rex = rex OR &H04

    IF opSize = 8 AND regField >= 4 AND regField <= 7 THEN
      rex = rex OR &H40
    END IF

    IF opSize = 16 THEN emitByteCode &H66
    IF rex > 0 THEN emitByteCode &H40 OR rex

    IF opSize = 8 THEN
      IF destIsMem = 1 THEN emitByteCode &H88 ELSE emitByteCode &H8A
    ELSE
      IF destIsMem = 1 THEN emitByteCode &H89 ELSE emitByteCode &H8B
    END IF
  ELSE
    regField = 0
    IF opSize = 16 THEN emitByteCode &H66
    IF rex > 0 THEN emitByteCode &H40 OR rex

    IF opSize = 8 THEN
      emitByteCode &HC6
    ELSE
      emitByteCode &HC7
    END IF
  END IF

  opHelperEmitSIBoperand regField, baseReg, indexReg, scaleVal, dispVal

  IF valType = OP_TYPE_IMM THEN
    IF opSize = 8 THEN
      emitByteCode valInfo AND 255
    ELSE
      IF opSize = 16 THEN
        emitByteCode valInfo AND 255
        emitByteCode (valInfo \ 256) AND 255
      ELSE
        emitBytes32 valInfo
      END IF
    END IF
  END IF

  opMov_SIB = tempRet

END FUNCTION ' opMov_SIB

''''''''''''''''''''''''
SUB opPopReg (wReg)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opPopReg"
  END IF

  ' RSP (4) and RBP (5) are strictly protected from POP to prevent stack frame desynchronization
  ' The backend epilogues in tira_EndAndProcess manually bypass this to tear down stack frames

  IF wReg < 0 OR wReg > 15 OR wReg = 4 OR wReg = 5 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(wReg)) + ") in opPopReg. RSP (4) and RBP (5) are protected."
  END IF

  ' Safety bounds check to ensure we do not underflow the compiler's tracked stack frame
  IF stack.currentStackOffset - 8 < 0 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: Stack underflow in opPopReg (attempted to pop past the start of the stack frame)."
  END IF

  IF wReg >= 8 THEN
    emitByteCode &H41
    emitByteCode (&H58 + (wReg AND 7))
  ELSE
    emitByteCode (&H58 + wReg)
  END IF

  stack.currentStackOffset = stack.currentStackOffset - 8
  ff = updateStackAlignment

END SUB ' opPopReg

''''''''''''''''''''''''
SUB opPushReg (wReg)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opPushReg"
  END IF

  ' Unlike POP which overwrites registers, PUSH only reads them
  ' Therefore RSP (4) and RBP (5) are safe to use here without strict manual protection
  checkRegisterBounds wReg, "opPushReg"

  IF wReg >= 8 THEN
    emitByteCode &H41
    emitByteCode (&H50 + (wReg AND 7))
  ELSE
    emitByteCode (&H50 + wReg)
  END IF

  stack.currentStackOffset = stack.currentStackOffset + 8
  ff = updateStackAlignment

END SUB ' opPushReg

''''''''''''''''''''''''
SUB opRet

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opRet"
  END IF

  emitByteCode &HC3

END SUB ' opRet

''''''''''''''''''''''''
FUNCTION opSetcc (passCondCode, passDestReg)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opSetcc"
  END IF

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM tempRet AS LONG

  checkRegisterBounds passDestReg, "opSetcc"

  tempRet = 0
  rex = 0

  IF passDestReg >= 8 THEN
    rex = rex OR &H01
  END IF

  ' If using SIL, DIL, BPL, SPL (regs 4-7) for an 8-bit operation, we need an empty REX prefix
  IF passDestReg >= 4 AND passDestReg <= 7 THEN
    rex = rex OR &H40
  END IF

  IF rex > 0 THEN emitByteCode &H40 OR rex

  emitByteCode &H0F
  emitByteCode &H90 + passCondCode

  modRM = &HC0 + (passDestReg AND 7)
  emitByteCode modRM

  opSetcc = tempRet

END FUNCTION ' opSetcc

''''''''''''''''''''''''
SUB opShift (wShiftType, wReg, wAmount, opSize)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opShift"
  END IF

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE

  IF wReg < 0 OR wReg > 15 OR wReg = 4 OR wReg = 5 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(wReg)) + ") in opShift. RSP (4) and RBP (5) are protected."
  END IF

  rex = 0

  IF opSize = 64 THEN rex = rex OR &H08
  IF wReg >= 8 THEN rex = rex OR &H01

  IF opSize = 16 THEN emitByteCode &H66
  IF rex > 0 THEN emitByteCode &H40 OR rex

  emitByteCode &HC1

  modRM = &HC0 + (wShiftType * 8) + (wReg AND 7)
  emitByteCode modRM

  emitByteCode (wAmount AND 255)

END SUB ' opShift

''''''''''''''''''''''''
FUNCTION opSSE (sseOpCode AS LONG, destType AS LONG, destInfo AS LONG, srcType AS LONG, srcInfo AS LONG, opMode AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opSSE"
  END IF

  DIM tempRet AS LONG
  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM prefix AS LONG
  DIM opByte AS LONG
  DIM isReverse AS LONG
  DIM primaryReg AS LONG
  DIM rmReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM disp32 AS LONG
  DIM opSize AS LONG

  tempRet = 0

  IF destType = OP_TYPE_REG THEN checkRegisterBounds destInfo, "opSSE"

  prefix = 0
  opByte = 0
  isReverse = 0
  opSize = 32

  IF opMode = MODE_SSE_SINGLE THEN prefix = &HF3
  IF opMode = MODE_SSE_DOUBLE THEN prefix = &HF2

  SELECT CASE sseOpCode

    CASE SSE_ADD: opByte = &H58
    CASE SSE_SUB: opByte = &H5C
    CASE SSE_MUL: opByte = &H59
    CASE SSE_DIV: opByte = &H5E

    CASE SSE_MOV
      IF destType = OP_TYPE_REG THEN
        opByte = &H10
      ELSE
        opByte = &H11
        isReverse = 1
      END IF

    CASE SSE_CVTSI2SD
      opSize = 64
      opByte = &H2A

    CASE SSE_CVTTSD2SI
      opSize = 64
      opByte = &H2C
      isReverse = 0

    CASE SSE_CVTSD2SI
      opSize = 64
      opByte = &H2D
      isReverse = 0

    CASE SSE_CVTSS2SD, SSE_CVTSD2SS
      opByte = &H5A

    CASE SSE_MOVQ_XMM_REG
      prefix = &H66
      opSize = 64
      opByte = &H6E
      isReverse = 0

    CASE SSE_MOVQ_REG_XMM
      prefix = &H66
      opSize = 64
      opByte = &H7E
      isReverse = 1

    CASE SSE_UCOMI
      IF opMode = MODE_SSE_SINGLE THEN prefix = 0
      IF opMode = MODE_SSE_DOUBLE THEN prefix = &H66
      opByte = &H2E

    CASE SSE_XOR
      IF opMode = MODE_SSE_SINGLE THEN prefix = 0
      IF opMode = MODE_SSE_DOUBLE THEN prefix = &H66
      opByte = &H57

  END SELECT ' sseOpCode

  IF isReverse = 1 THEN
    primaryReg = srcInfo
    rmReg = destInfo
  ELSE
    primaryReg = destInfo
    rmReg = srcInfo
  END IF

  baseReg = REG_NONE
  IF isReverse = 1 THEN
    IF destType = OP_TYPE_REG THEN baseReg = rmReg
    IF destType = OP_TYPE_MEM_RSP THEN baseReg = 4
    IF destType = OP_TYPE_MEM_RBP THEN baseReg = 5
    IF destType = OP_TYPE_MEM_REG OR destType = OP_TYPE_MEM_REG_DISP8 OR destType = OP_TYPE_MEM_REG_DISP32 THEN baseReg = rmReg AND 15
  ELSE
    IF srcType = OP_TYPE_REG THEN baseReg = rmReg
    IF srcType = OP_TYPE_MEM_RSP THEN baseReg = 4
    IF srcType = OP_TYPE_MEM_RBP THEN baseReg = 5
    IF srcType = OP_TYPE_MEM_REG OR srcType = OP_TYPE_MEM_REG_DISP8 OR srcType = OP_TYPE_MEM_REG_DISP32 THEN baseReg = rmReg AND 15
  END IF

  rex = calcRex(opSize, primaryReg, baseReg, REG_NONE)

  IF prefix <> 0 THEN emitByteCode prefix
  IF rex > 0 THEN emitByteCode rex
  emitByteCode &H0F
  emitByteCode opByte

  IF isReverse = 1 THEN

    SELECT CASE destType

      CASE OP_TYPE_REG
        modRM = &HC0 + ((primaryReg AND 7) * 8) + (rmReg AND 7)
        emitByteCode modRM

      CASE OP_TYPE_MEM_RIP
        modRM = ((primaryReg AND 7) * 8) + 5
        emitByteCode modRM
        tempRet = stream.emitPos
        emitBytes32 0

      CASE OP_TYPE_MEM_RSP
        IF rmReg >= -128 AND rmReg <= 127 THEN
          emitMemoryOperand primaryReg, 4, 8, rmReg
        ELSE
          emitMemoryOperand primaryReg, 4, 32, rmReg
        END IF

      CASE OP_TYPE_MEM_RBP
        emitMemoryOperand primaryReg, 5, 32, rmReg

      CASE OP_TYPE_MEM_REG
        baseReg = rmReg AND 15
        emitMemoryOperand primaryReg, baseReg, 0, 0

      CASE OP_TYPE_MEM_REG_DISP8
        baseReg = rmReg AND 15
        disp8 = ((rmReg - baseReg) \ 256) AND 255
        emitMemoryOperand primaryReg, baseReg, 8, disp8

      CASE OP_TYPE_MEM_REG_DISP32
        baseReg = rmReg AND 15
        disp32 = (rmReg - baseReg) \ 256
        emitMemoryOperand primaryReg, baseReg, 32, disp32

    END SELECT ' destType

  ELSE

    SELECT CASE srcType

      CASE OP_TYPE_REG
        modRM = &HC0 + ((primaryReg AND 7) * 8) + (rmReg AND 7)
        emitByteCode modRM

      CASE OP_TYPE_MEM_RIP
        modRM = ((primaryReg AND 7) * 8) + 5
        emitByteCode modRM
        tempRet = stream.emitPos
        emitBytes32 0

      CASE OP_TYPE_MEM_RSP
        IF rmReg >= -128 AND rmReg <= 127 THEN
          emitMemoryOperand primaryReg, 4, 8, rmReg
        ELSE
          emitMemoryOperand primaryReg, 4, 32, rmReg
        END IF

      CASE OP_TYPE_MEM_RBP
        emitMemoryOperand primaryReg, 5, 32, rmReg

      CASE OP_TYPE_MEM_REG
        baseReg = rmReg AND 15
        emitMemoryOperand primaryReg, baseReg, 0, 0

      CASE OP_TYPE_MEM_REG_DISP8
        baseReg = rmReg AND 15
        disp8 = ((rmReg - baseReg) \ 256) AND 255
        emitMemoryOperand primaryReg, baseReg, 8, disp8

      CASE OP_TYPE_MEM_REG_DISP32
        baseReg = rmReg AND 15
        disp32 = (rmReg - baseReg) \ 256
        emitMemoryOperand primaryReg, baseReg, 32, disp32

    END SELECT ' srcType

  END IF

  opSSE = tempRet

END FUNCTION ' opSSE

''''''''''''''''''''''''
SUB opString (wStrOp, wPrefix, wSize)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opString"
  END IF

  IF wPrefix = REP_REP THEN emitByteCode &HF3
  IF wPrefix = REP_REPNE THEN emitByteCode &HF2

  IF wSize = 16 THEN emitByteCode &H66
  IF wSize = 64 THEN emitByteCode &H48

  baseOp = 0

  SELECT CASE wStrOp

    CASE STR_MOVS
      baseOp = &HA4

    CASE STR_CMPS
      baseOp = &HA6

    CASE STR_STOS
      baseOp = &HAA

    CASE STR_LODS
      baseOp = &HAC

    CASE STR_SCAS
      baseOp = &HAE

  END SELECT ' wStrOp

  IF wSize <> 8 THEN baseOp = baseOp + 1

  emitByteCode baseOp

END SUB ' opString

''''''''''''''''''''''''
SUB opSubRsp32 (wVal AS LONG)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opSubRsp32"
  END IF

  'Using opALU instead of this function will output 4 bytes instead of 7 bytes since opALU compresses values under 128

  emitByteCode &H48 ' REX.W
  emitByteCode &H81 ' ALU format 81
  emitByteCode &HEC ' ModRM for SUB RSP
  emitBytes32 wVal

  stack.currentStackOffset = stack.currentStackOffset + wVal
  ff = updateStackAlignment

END SUB ' opSubRsp32

''''''''''''''''''''''''
FUNCTION opTest (destType, destInfo AS LONG, srcType, srcInfo AS _INTEGER64, opSizeOrFlag)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opTest"
  END IF

  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM disp32 AS LONG
  DIM tempRet AS LONG

  DIM opBase85 AS LONG
  DIM opBaseF7 AS LONG

  tempRet = 0

  IF destType = OP_TYPE_REG THEN checkRegisterBounds destInfo, "opTest"

  opBase85 = &H85
  opBaseF7 = &HF7

  IF opSizeOrFlag = 8 THEN
    opBase85 = &H84
    opBaseF7 = &HF6
  END IF

  SELECT CASE destType

    CASE OP_TYPE_REG
      destReg = destInfo

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Register
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, destReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          emitByteCode opBase85
          modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_IMM ' Immediate-to-Register
          rex = calcRex(opSizeOrFlag, 0, destReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex

          emitByteCode opBaseF7
          modRM = &HC0 + (destReg AND 7) ' reg field is 0 for TEST imm
          emitByteCode modRM

          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

        CASE OP_TYPE_MEM_RBP ' Memory (RBP-relative)
          rex = calcRex(opSizeOrFlag, destReg, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          emitMemoryOperand destReg, 5, 32, srcInfo

        CASE OP_TYPE_MEM_REG_DISP32 ' Memory (Register-Indirect with 32-bit disp)
          baseReg = srcInfo AND 15
          disp32 = (srcInfo - baseReg) \ 256
          rex = calcRex(opSizeOrFlag, destReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          emitMemoryOperand destReg, baseReg, 32, disp32

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RIP ' Memory (RIP-relative)

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          modRM = ((srcReg AND 7) * 8) + 5
          emitByteCode modRM
          tempRet = stream.emitPos
          emitBytes32 0
        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBaseF7
          modRM = 5 ' reg field is 0
          emitByteCode modRM
          tempRet = stream.emitPos
          emitBytes32 0
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RSP ' Memory (RSP-relative)

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitMemoryOperand srcReg, 4, 8, destInfo
          ELSE
            emitMemoryOperand srcReg, 4, 32, destInfo
          END IF
        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, 4, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBaseF7
          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitMemoryOperand 0, 4, 8, destInfo
          ELSE
            emitMemoryOperand 0, 4, 32, destInfo
          END IF
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RBP ' Memory (RBP-relative)

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo
          rex = calcRex(opSizeOrFlag, srcReg, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          emitMemoryOperand srcReg, 5, 32, destInfo
        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, 5, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBaseF7
          emitMemoryOperand 0, 5, 32, destInfo
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG
      baseReg = destInfo AND 15

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          emitMemoryOperand srcReg, baseReg, 0, 0
        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBaseF7
          emitMemoryOperand 0, baseReg, 0, 0
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = destInfo AND 15
      disp8 = ((destInfo - baseReg) \ 256) AND 255

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          emitMemoryOperand srcReg, baseReg, 8, disp8
        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBaseF7
          emitMemoryOperand 0, baseReg, 8, disp8
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_REG_DISP32
      baseReg = destInfo AND 15
      disp32 = (destInfo - baseReg) \ 256

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBase85
          emitMemoryOperand srcReg, baseReg, 32, disp32
        CASE OP_TYPE_IMM
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          emitByteCode opBaseF7
          emitMemoryOperand 0, baseReg, 32, disp32
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_GS_ABS32 ' Register/Immediate-to-Memory (GS Segment Absolute 32-bit)

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, srcReg, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          modRM = ((srcReg AND 7) * 8) + 4
          emitByteCode modRM
          emitByteCode &H25
          emitBytes32 destInfo

        CASE OP_TYPE_IMM
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, 0, REG_NONE, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          modRM = 4
          emitByteCode modRM
          emitByteCode &H25
          emitBytes32 destInfo
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_GS_REG_DISP32 ' Register/Immediate-to-Memory (GS Segment Register-Indirect 32-bit disp)
      baseReg = destInfo AND 15
      disp32 = (destInfo - baseReg) \ 256

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, srcReg, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &H88 ELSE emitByteCode &H89
          emitMemoryOperand srcReg, baseReg, 32, disp32

        CASE OP_TYPE_IMM
          emitByteCode &H65
          rex = calcRex(opSizeOrFlag, 0, baseReg, REG_NONE)
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode rex
          IF opSizeOrFlag = 8 THEN emitByteCode &HC6 ELSE emitByteCode &HC7
          emitMemoryOperand 0, baseReg, 32, disp32
          IF opSizeOrFlag = 8 THEN
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 16 THEN
              emitByteCode (srcInfo AND 255)
              emitByteCode ((srcInfo \ 256) AND 255)
            ELSE
              emitBytes32 srcInfo
            END IF
          END IF

      END SELECT ' srcType

  END SELECT ' destType

  opTest = tempRet

END FUNCTION ' opTest

''''''''''''''''''''''''
FUNCTION opUnary (passOpCode, passDestType, passDestInfo, passOpSize)

  IF TIRA_OP_SAFETY = 1 THEN
    IF t.IsActive < 2 THEN ESCAPETEXT "FATAL COMPILER ERROR: UNAUTHORIZED OP CALL IN opUnary"
  END IF

  DIM rex AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM baseReg AS LONG
  DIM disp AS LONG
  DIM disp32 AS LONG
  DIM tempRet AS LONG

  tempRet = 0

  IF passDestType = OP_TYPE_REG THEN
    IF passDestInfo < 0 OR passDestInfo > 15 OR passDestInfo = 4 OR passDestInfo = 5 THEN
      ESCAPETEXT "FATAL COMPILER ERROR: Invalid reg target (" + LTRIM$(STR$(passDestInfo)) + ") in opUnary. RSP (4) and RBP (5) are protected."
    END IF
  END IF

  SELECT CASE passDestType

    CASE OP_TYPE_REG
      baseReg = passDestInfo
      rex = calcRex(passOpSize, REG_NONE, baseReg, REG_NONE)
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      modRM = &HC0 + (passOpCode * 8) + (baseReg AND 7)
      emitByteCode modRM

    CASE OP_TYPE_MEM_RIP
      rex = calcRex(passOpSize, REG_NONE, REG_NONE, REG_NONE)
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      modRM = (passOpCode * 8) + 5
      emitByteCode modRM
      tempRet = stream.emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      disp = passDestInfo
      rex = calcRex(passOpSize, REG_NONE, 4, REG_NONE)
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      IF disp >= -128 AND disp <= 127 THEN
        emitMemoryOperand passOpCode, 4, 8, disp
      ELSE
        emitMemoryOperand passOpCode, 4, 32, disp
      END IF

    CASE OP_TYPE_MEM_RBP
      disp = passDestInfo
      rex = calcRex(passOpSize, REG_NONE, 5, REG_NONE)
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      emitMemoryOperand passOpCode, 5, 32, disp

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = passDestInfo AND 15
      disp8 = ((passDestInfo - baseReg) \ 256) AND 255
      rex = calcRex(passOpSize, REG_NONE, baseReg, REG_NONE)
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      emitMemoryOperand passOpCode, baseReg, 8, disp8

    CASE OP_TYPE_MEM_REG_DISP32
      baseReg = passDestInfo AND 15
      disp32 = (passDestInfo - baseReg) \ 256
      rex = calcRex(passOpSize, REG_NONE, baseReg, REG_NONE)
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      emitMemoryOperand passOpCode, baseReg, 32, disp32

  END SELECT ' passDestType

  opUnary = tempRet

END FUNCTION ' opUnary

''''''''''''''''''''''''
FUNCTION parse_ASC$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM dataPtr$
  DIM strLen$
  DIM validAscLbl$
  DIM errStr$
  DIM byteVal$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED ASC", ASIS, 0
    parse_ASC$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED ASC", ASIS, 0
    parse_ASC$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_ASC$ = ""
    EXIT FUNCTION
  END IF
  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES STRING", ASIS, 0
    parse_ASC$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("ASC", "_VAL")
  IF scratchName$ = "" THEN
    parse_ASC$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, "0"

  dataPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  validAscLbl$ = tiraLabelCreateNew$("VALID_ASC")
  tiraJmpCond "JG", strLen$, "0", validAscLbl$

  errStr$ = CHR$(34) + "PROGRAM TERMINATED: ILLEGAL FUNCTION CALL IN ASC() ON LINE " + retLineNumberStr$ + CHR$(34)
  tiraCall "RT_PRINT_STR", 1, errStr$
  tiraCall "RT_CRLF", 0, ""
  tiraJmp "@END_PROGRAM"

  tiraLabel validAscLbl$

  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, byteVal$ + ", " + dataPtr$
  tiraAssign resVar$, byteVal$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_ASC$ = scratchName$

END FUNCTION ' parse_ASC$

''''''''''''''''''''''''
FUNCTION parse_ATN$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM argFloat$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED ATN", ASIS, 0
    parse_ATN$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED ATN", ASIS, 0
    parse_ATN$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_ATN$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_ATN$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("ATN", "_VAL")
  IF scratchName$ = "" THEN
    parse_ATN$ = ""
    EXIT FUNCTION
  END IF

  ' Explicitly override the integer prefix rule to safely route as float
  ff = resolveSymbol(scratchName$)
  IF ff = 1 THEN symbols(returnedData2).DataType = TYPE_DOUBLE

  resVar$ = tiraDimVar$("T", TYPE_DOUBLE)

  ' Coerce the argument to a double for the external IAT function
  IF exprIs.DataType <> TYPE_DOUBLE THEN
    argFloat$ = tiraDimVar$("T", TYPE_DOUBLE)
    tiraAssign argFloat$, arg1$
    arg1$ = argFloat$
  END IF

  tiraCall "IAT_ATAN", 1, arg1$
  tiraNew TC_GET_RET, resVar$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_DOUBLE
  exprIs.IsTemp = 1
  parse_ATN$ = scratchName$

END FUNCTION ' parse_ATN$

''''''''''''''''''''''''
FUNCTION parse_BEEP (startIdx)

  DIM endIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  ff = verifyNoExtraTokens(endIdx, startIdx, "BEEP")
  IF ff = 0 THEN EXIT FUNCTION

  tira_Start
  tiraCall "IAT_BEEP", 2, "800, 250"
  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_BEEP = 1

END FUNCTION ' parse_BEEP

''''''''''''''''''''''''
FUNCTION parse_CASE (startIdx)

  DIM endIdx AS LONG
  DIM hiddenVarIdx AS LONG
  DIM selectType AS LONG
  DIM selID AS LONG
  DIM caseID AS LONG
  DIM exprStart AS LONG
  DIM exprEnd AS LONG
  DIM toIdx AS LONG
  DIM hasTo AS LONG
  DIM tVal AS LONG
  DIM opType AS LONG
  DIM relStart AS LONG
  DIM nxtVal AS LONG
  DIM commaIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "CASE WITHOUT SELECT", ASIS, 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_SELECT THEN
    throwCompilerError "CASE NOT INSIDE SELECT", ASIS, 0
    EXIT FUNCTION
  END IF

  hiddenVarIdx = ctrls(ctrlCount - 1).SelectVarIdx
  selectType = ctrls(ctrlCount - 1).SelectDataType
  selID = ctrls(ctrlCount - 1).Patch1
  caseID = ctrls(ctrlCount - 1).SelectCaseSeen

  hiddenName$ = RTRIM$(symbols(hiddenVarIdx).RecordName)
  endSelLbl$ = "@SEL_END_" + cTrNum$(selID)
  nextCaseLbl$ = "@SEL_NEXT_" + cTrNum$(selID) + "_" + cTrNum$(caseID)
  bodyLbl$ = "@SEL_BODY_" + cTrNum$(selID) + "_" + cTrNum$(caseID)

  tira_Start

  IF caseID > 0 THEN
    ' Jump to end of SELECT block because the PREVIOUS case just finished executing its body
    tiraScheduleHeapReset
    tiraJmp endSelLbl$
    ' The previous case's conditions would skip to right here if they all failed
    prevNextLbl$ = "@SEL_NEXT_" + cTrNum$(selID) + "_" + cTrNum$(caseID - 1)
    tiraLabel prevNextLbl$
  END IF

  exprStart = startIdx + 1

  IF exprStart <= endIdx THEN
    IF lineTokenVals(exprStart) = 256 + ASC(":") THEN
      exprStart = exprStart + 1
    END IF
  END IF

  ' Check for CASE ELSE
  IF exprStart <= endIdx THEN
    IF lineTokenVals(exprStart) = TOK_ELSE THEN
      ' Since it is CASE ELSE, execution falls right through, no conditions
      tiraScheduleHeapReset
      tira_EndAndProcess

      ctrls(ctrlCount - 1).SelectCaseSeen = caseID + 1

      return2 endIdx
      parse_CASE = 1
      EXIT FUNCTION
    END IF
  END IF

  ' Evaluate a comma-separated list of expressions
  DO WHILE exprStart <= endIdx
    exprEnd = endIdx

    commaIdx = findComma(exprStart, endIdx)
    IF commaIdx > 0 THEN
      exprEnd = commaIdx - 1
    END IF

    hasTo = 0
    toIdx = 0
    ff = findNextTokenAtDepth0(exprStart, exprEnd, TOK_TO)
    IF ff = 1 THEN
      hasTo = 1
      toIdx = returnedData2
    END IF

    IF hasTo = 1 THEN
      '''' Case X to Y

      IF compileClassicMode = 1 THEN expectedSymType = selectType
      lhsVar$ = tiraParseExpression$(exprStart, toIdx - 1, 1)
      IF lhsVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      IF selectType = TYPE_STRING AND exprIs.DataType <> TYPE_STRING THEN
        tira_Cancel
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF
      IF selectType <> TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        tira_Cancel
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF

      IF compileClassicMode = 1 THEN expectedSymType = selectType
      rhsVar$ = tiraParseExpression$(toIdx + 1, exprEnd, 1)
      IF rhsVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      IF selectType = TYPE_STRING AND exprIs.DataType <> TYPE_STRING THEN
        tira_Cancel
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF
      IF selectType <> TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        tira_Cancel
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF

      lblSkip$ = tiraLabelCreateNew$("SKIP_CASE")
      tiraJmpCond "JL", hiddenName$, lhsVar$, lblSkip$
      tiraJmpCond "JLE", hiddenName$, rhsVar$, bodyLbl$
      tiraLabel lblSkip$

    ELSE
      '''' Case relational / equals

      opType = 0 ' 0 =, 1 <, 2 >, 3 <=, 4 >=, 5 <>
      relStart = exprStart

      IF relStart <= exprEnd THEN
        IF lineTokenVals(relStart) = 0 THEN
          IF UCASE$(lineTokens$(relStart)) = "IS" THEN
            relStart = relStart + 1
          END IF
        END IF
      END IF

      IF relStart <= exprEnd THEN
        tVal = lineTokenVals(relStart)

        SELECT CASE tVal

          CASE 256 + ASC("=")
            opType = 0
            relStart = relStart + 1

          CASE 256 + ASC("<")
            IF relStart + 1 <= exprEnd THEN
              nxtVal = lineTokenVals(relStart + 1)
              SELECT CASE nxtVal

                CASE 256 + ASC("=")
                  opType = 3
                  relStart = relStart + 2

                CASE 256 + ASC(">")
                  opType = 5
                  relStart = relStart + 2

                CASE ELSE
                  opType = 1
                  relStart = relStart + 1

              END SELECT ' nxtVal

            ELSE
              opType = 1
              relStart = relStart + 1
            END IF

          CASE 256 + ASC(">")
            IF relStart + 1 <= exprEnd THEN
              nxtVal = lineTokenVals(relStart + 1)
              IF nxtVal = 256 + ASC("=") THEN
                opType = 4
                relStart = relStart + 2
              ELSE
                opType = 2
                relStart = relStart + 1
              END IF
            ELSE
              opType = 2
              relStart = relStart + 1
            END IF

        END SELECT ' tVal

      END IF

      IF compileClassicMode = 1 THEN expectedSymType = selectType
      rhsVar$ = tiraParseExpression$(relStart, exprEnd, 1)
      IF rhsVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      IF selectType = TYPE_STRING AND exprIs.DataType <> TYPE_STRING THEN
        tira_Cancel
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF
      IF selectType <> TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        tira_Cancel
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF

      condStr$ = ""

      SELECT CASE opType

        CASE 0: condStr$ = "JE"
        CASE 1: condStr$ = "JL"
        CASE 2: condStr$ = "JG"
        CASE 3: condStr$ = "JLE"
        CASE 4: condStr$ = "JGE"
        CASE 5: condStr$ = "JNE"

      END SELECT ' opType

      tiraJmpCond condStr$, hiddenName$, rhsVar$, bodyLbl$

    END IF

    exprStart = exprEnd + 2
  LOOP

  ' If not equal to any of the above comma-separated checks, skip to the next CASE
  tiraScheduleHeapReset
  tiraJmp nextCaseLbl$

  ' Anchor the body execution block here for matches
  tiraLabel bodyLbl$
  tiraScheduleHeapReset

  tira_EndAndProcess

  ctrls(ctrlCount - 1).SelectCaseSeen = caseID + 1

  return2 endIdx
  parse_CASE = 1

END FUNCTION ' parse_CASE

''''''''''''''''''''''''
FUNCTION parse_CHR$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM dataPtr$
  DIM descPtr$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED CHR$", ASIS, 0
    parse_CHR$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED CHR$", ASIS, 0
    parse_CHR$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_CHR$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_CHR$ = ""
    EXIT FUNCTION
  END IF

  arg1$ = tiraForceInt$(arg1$)

  scratchName$ = tiraResolveHoistVar$("CHR", "_DESC$")
  IF scratchName$ = "" THEN
    parse_CHR$ = ""
    EXIT FUNCTION
  END IF

  dataPtr$ = tiraAllocTempMem$("1")

  ' Write the payload character to the heap natively
  tiraWriteMem dataPtr$, arg1$, "1"

  ' Build the String Descriptor directly on the Scratchpad memory
  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$

  ' Ensure Flags are set to 0 (No Free Required on Temp Heap)
  tiraBuildStringDescriptor descPtr$, dataPtr$, "1", "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_CHR$ = scratchName$

END FUNCTION ' parse_CHR$

''''''''''''''''''''''''
FUNCTION parse_CLOSE (startIdx)

  DIM commaIdx AS LONG
  DIM itemStart AS LONG
  DIM itemEnd AS LONG
  DIM fileNumStart AS LONG
  DIM fileNumVar$
  DIM baseArr$
  DIM iterVar$
  DIM loopTop$
  DIM loopEnd$
  DIM slotAddr$
  DIM handleVar$
  DIM skipClose$
  DIM skipClose2$

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tira_Start

  baseArr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, baseArr$, "!G_LAYOUT_FILE_HANDLES_ARR", ""

  IF endIdx < startIdx + 1 THEN
    ' Close all files iteratively (1 to 255)
    iterVar$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign iterVar$, "1"

    loopTop$ = tiraLabelCreateNew$("CLOSE_LOOP")
    loopEnd$ = tiraLabelCreateNew$("CLOSE_END")

    tiraLabel loopTop$
    tiraJmpCond "JG", iterVar$, "255", loopEnd$

    slotAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraLeaSIB slotAddr$, baseArr$, iterVar$, "8"

    handleVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_READ_MEM, handleVar$ + ", " + slotAddr$

    skipClose$ = tiraLabelCreateNew$("SKIP_CLOSE")
    tiraJmpCond "JE", handleVar$, "0", skipClose$
    tiraJmpCond "JE", handleVar$, "-1", skipClose$ ' INVALID_HANDLE_VALUE (-1)

    tiraCall "IAT_CLOSEHANDLE", 1, handleVar$
    tiraWriteMem slotAddr$, "0", "8"

    tiraLabel skipClose$
    tiraOp TC_ADD, iterVar$, iterVar$, "1"
    tiraJmp loopTop$

    tiraLabel loopEnd$
  ELSE
    ' Close specifically identified files mapped by comma boundaries
    itemStart = startIdx + 1
    DO WHILE itemStart <= endIdx
      itemEnd = endIdx
      commaIdx = findComma(itemStart, endIdx)
      IF commaIdx > 0 THEN itemEnd = commaIdx - 1

      fileNumStart = itemStart

      ' Strip the # symbol so the expression evaluates properly
      IF lineTokens$(fileNumStart) = "#" THEN
        fileNumStart = fileNumStart + 1
      ELSE
        IF LEFT$(lineTokens$(fileNumStart), 1) = "#" THEN
          lineTokens$(fileNumStart) = MID$(lineTokens$(fileNumStart), 2)
        END IF
      END IF

      fileNumVar$ = tiraParseExpressionInt$(fileNumStart, itemEnd, ALIM, "FILENUM MUST BE NUMERIC")
      IF fileNumVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      slotAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraLeaSIB slotAddr$, baseArr$, fileNumVar$, "8"

      handleVar$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraNew TC_READ_MEM, handleVar$ + ", " + slotAddr$

      skipClose2$ = tiraLabelCreateNew$("SKIP_CLOSE")
      tiraJmpCond "JE", handleVar$, "0", skipClose2$
      tiraJmpCond "JE", handleVar$, "-1", skipClose2$

      tiraCall "IAT_CLOSEHANDLE", 1, handleVar$
      tiraWriteMem slotAddr$, "0", "8"

      tiraLabel skipClose2$

      itemStart = itemEnd + 2
    LOOP
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_CLOSE = 1

END FUNCTION ' parse_CLOSE

''''''''''''''''''''''''
FUNCTION parse_CLS (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  argStr$ = ""

  tira_Start

  ' Check if there is an argument provided for CLS
  IF endIdx > startIdx THEN
    argStr$ = tiraParseExpressionInt$(startIdx + 1, endIdx, ALIM, "CLS REQUIRES NUMERIC ARGUMENT")
    IF argStr$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
  END IF

  ' Handle standard console clearing
  IF compileHasGraphics = 0 THEN
    ' Get the symbol index for the pre-built clear screen string
    ff = resolveSymbol("!G_IO_CLSSCR_DESC$")
    IF ff = 0 THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
    clsScratchIdx = returnedData2
    ' Fill the clear screen string with spaces and a newline
    strVarData$(clsScratchIdx) = STRING$(120, 32) + CHR$(13) + CHR$(10)

    ' Create a temporary variable to hold the console output handle
    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    ' Call Windows API to get the standard output handle
    tiraCall "IAT_GETSTDHANDLE", 1, "-11"
    ' Retrieve the returned handle into the temp variable
    tiraNew TC_GET_RET, hndVar$

    ' Create a variable for the starting row
    topVar$ = tiraDimVar$("T", TYPE_LONG)
    ' Set starting row to zero
    tiraAssign topVar$, "0"

    ' Create a variable for the bottom row
    botVar$ = tiraDimVar$("T", TYPE_LONG)
    ' Set bottom row to twenty-five
    tiraAssign botVar$, "25"

    ' Create a variable for the total lines to clear
    linesVar$ = tiraDimVar$("T", TYPE_LONG)
    ' Calculate total lines by subtracting top from bottom
    tiraOp TC_SUB, linesVar$, botVar$, topVar$

    ' Create a variable for the string descriptor pointer
    strDesc$ = tiraDimVar$("T", TYPE_INTEGER64)
    ' Assign the value of the clear screen string to the descriptor pointer
    tiraAssign strDesc$, "!G_IO_CLSSCR_DESC$"

    ' Create a variable for the string data pointer
    strData$ = tiraDimVar$("T", TYPE_INTEGER64)
    ' Read the memory address of the string data from the descriptor
    tiraNew TC_READ_MEM, strData$ + ", " + strDesc$

    ' Create a variable for the string length
    strLen$ = tiraDimVar$("T", TYPE_LONG)
    ' Advance the descriptor pointer by eight bytes to point to the length
    tiraOp TC_ADD, strDesc$, strDesc$, "8"
    ' Read the length from the descriptor memory
    tiraNew TC_READ_MEM, strLen$ + ", " + strDesc$

    ' Create a variable for the bytes written pointer used by WriteFile
    numWrt$ = tiraDimVar$("T", TYPE_LONG)
    numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

    ' Create a new jump label for the clearing loop
    loopLbl$ = tiraLabelCreateNew$("CLS_LOOP")
    ' Place the loop label in the TIRA queue
    tiraLabel loopLbl$

    ' Create a variable for the Windows API COORD structure
    coord$ = tiraDimVar$("T", TYPE_LONG)
    ' Shift the Y coordinate to the high word to format the COORD value
    tiraOp TC_MUL, coord$, topVar$, "65536"

    ' Move the console cursor to the current row
    tiraCall "IAT_SETCONSOLECURSORPOSITION", 2, hndVar$ + ", " + coord$
    ' Write the blank spaces to the row
    tiraCall "IAT_WRITEFILE", 5, hndVar$ + ", " + strData$ + ", " + strLen$ + ", " + numWrtPtr$ + ", 0"

    ' Increment the current row variable
    tiraOp TC_ADD, topVar$, topVar$, "1"
    ' Decrement the remaining lines counter
    tiraOp TC_SUB, linesVar$, linesVar$, "1"
    ' Jump back to the top of the loop if lines remain
    tiraJmpCond "JG", linesVar$, "0", loopLbl$

    ' Reset the cursor to the top left of the console when finished
    tiraCall "IAT_SETCONSOLECURSORPOSITION", 2, hndVar$ + ", 0"

  ELSE
    ' Handle graphics window clearing
    ' Default to using the parsed argument for the clear type
    clsType$ = argStr$
    ' If no argument was provided default to type zero which clears everything
    IF clsType$ = "" THEN clsType$ = "0"

    ' Create a label to skip clearing the graphical framebuffer
    skipFb$ = tiraLabelCreateNew$("SKIP_FB")
    ' Jump over framebuffer clearing if type two is requested
    tiraJmpCond "EQ", clsType$, "2", skipFb$

    ' Create a variable for the framebuffer address
    fbPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    ' Retrieve the hardware framebuffer pointer using the BACK buffer
    tiraAssign fbPtr$, "!G_FRAMEBUF_BACK_PTR"

    ' Create a variable for the total pixel count
    fbSize$ = tiraDimVar$("T", TYPE_LONG)
    ' Set the pixel count based on the current graphics configuration
    tiraAssign fbSize$, LTRIM$(STR$(gfxConfig.SizeX * gfxConfig.SizeY))

    ' Zero out the entire framebuffer memory block
    tiraMemSet fbPtr$, "0", fbSize$

    ' Place the skip framebuffer label
    tiraLabel skipFb$

    ' Reset the text cursor X position
    tiraAssign "!G_GFX_CUR_X_VAL", "0"
    ' Reset the text cursor Y position
    tiraAssign "!G_GFX_CUR_Y_VAL", "0"

    ' Create a label to skip clearing the text overlay buffer
    skipTxt$ = tiraLabelCreateNew$("SKIP_TXT")
    ' Jump over text clearing if type one is requested
    tiraJmpCond "EQ", clsType$, "1", skipTxt$

    ' Clear the text buffer by resetting its count to zero
    tiraAssign "!G_GFX_BUF_COUNT_BACK_VAL", "0"

    ' Place the skip text buffer label
    tiraLabel skipTxt$

    tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

    ' Queue a redraw command to refresh the graphics window using the new thread-safe swap
    skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
    tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
    tiraInjectPendingDisplayFlush
    tiraLabel skipAutoLbl$

  END IF

  tiraScheduleHeapReset
  ' Compile the queued TIRA commands into machine code
  tira_EndAndProcess

  return2 endIdx
  parse_CLS = 1

END FUNCTION ' parse_CLS

''''''''''''''''''''''''
FUNCTION parse_CIRCLE (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF compileHasGraphics = 0 THEN
    throwCompilerError "CIRCLE REQUIRES #GRAPHICS", ASIS, 0
    EXIT FUNCTION
  END IF

  tokIdx = startIdx + 1

  IF tokIdx > endIdx THEN
    throwCompilerError "EXPECTED ( AFTER CIRCLE", ASIS, 0
    EXIT FUNCTION
  END IF

  IF lineTokenVals(tokIdx) <> 256 + ASC("(") THEN
    throwCompilerError "EXPECTED ( AFTER CIRCLE", ASIS, 0
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 1, endIdx)
  comma2 = 0
  IF comma1 > 0 THEN
    comma2 = findComma(comma1 + 1, endIdx)
  END IF

  IF comma1 = 0 THEN
    throwCompilerError "CIRCLE MISSING RADIUS", ASIS, 0
    EXIT FUNCTION
  END IF

  cComma = retCoordinateBoundaries(startIdx + 1, comma1 - 1)
  IF cComma = 0 THEN
    throwCompilerError "CIRCLE MISSING X, Y", ASIS, 0
    EXIT FUNCTION
  END IF
  cStart = returnedData2
  cEnd = returnedData3

  tira_Start

  x$ = tiraParseExpressionInt$(cStart, cComma - 1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF x$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  y$ = tiraParseExpressionInt$(cComma + 1, cEnd, ALIM, "COORDINATE MUST BE NUMERIC")
  IF y$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  rEnd = endIdx
  IF comma2 > 0 THEN rEnd = comma2 - 1

  IF comma1 + 1 > rEnd THEN
    throwCompilerError "CIRCLE MISSING RADIUS", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF

  r$ = tiraParseExpressionInt$(comma1 + 1, rEnd, ALIM, "RADIUS MUST BE NUMERIC")
  IF r$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  IF comma2 > 0 THEN
    IF comma2 + 1 > endIdx THEN
      c$ = "!G_GFX_FG_VAL"
    ELSE
      c$ = tiraParseExpressionInt$(comma2 + 1, endIdx, ALIM, "COLOR MUST BE NUMERIC")
      IF c$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF
  ELSE
    c$ = "!G_GFX_FG_VAL"
  END IF

  tiraCall "RT_CIRCLE", 4, x$ + ", " + y$ + ", " + r$ + ", " + c$

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_CIRCLE = 1

END FUNCTION ' parse_CIRCLE

''''''''''''''''''''''''
FUNCTION parse_COLOR (startIdx)

  DIM commaPos AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tira_Start

  commaPos = findComma(startIdx + 1, endIdx)

  IF commaPos = 0 THEN
    ' No comma found, so there is only a foreground argument - COLOR fg
    ' Ensure the statement is not just "COLOR" with no arguments
    IF endIdx >= startIdx + 1 THEN
      hasFg = 1
      fgStr$ = tiraParseExpressionInt$(startIdx + 1, endIdx, ALIM, "COLOR REQUIRES NUMERIC")
      IF fgStr$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF
  ELSE
    ' Comma was found. Check for arguments on either side of it
    IF commaPos > startIdx + 1 THEN
      ' Argument exists before the comma - COLOR fg, ...
      hasFg = 1
      fgStr$ = tiraParseExpressionInt$(startIdx + 1, commaPos - 1, ALIM, "COLOR REQUIRES NUMERIC")
      IF fgStr$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF

    IF commaPos < endIdx THEN
      ' Argument exists after the comma - COLOR ..., bg
      hasBg = 1
      bgStr$ = tiraParseExpressionInt$(commaPos + 1, endIdx, ALIM, "COLOR REQUIRES NUMERIC")
      IF bgStr$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF
  END IF

  ' Process foreground
  IF hasFg = 1 THEN
    tiraAssign "!G_GFX_LAST_FG_VAL", fgStr$
    tiraAssign "!G_GFX_COLOR_INIT_FLAG", "1"
  ELSE
    ' No foreground was provided, so load the last used one or the default.
    skipInitLbl$ = tiraLabelCreateNew$("SKIP_INIT")
    fgStr$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign fgStr$, "!G_GFX_LAST_FG_VAL"
    tiraJmpCond "JNE", "!G_GFX_COLOR_INIT_FLAG", "0", skipInitLbl$
    tiraAssign fgStr$, "7" ' Default FG is 7 (Light Gray) in standard console
    tiraLabel skipInitLbl$
  END IF

  ' Process background
  IF hasBg = 1 THEN
    tiraAssign "!G_GFX_LAST_BG_VAL", bgStr$
  ELSE
    ' No background was provided, so load the last used one.
    bgStr$ = "!G_GFX_LAST_BG_VAL"
  END IF

  IF compileHasGraphics = 1 THEN
    ' Mask to 0-255 using primitive AND
    fgMask$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_AND, fgMask$, fgStr$, "255"

    ' Extract the pointer to the !G_GFX_PALETTE_DESC$ descriptor
    palDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraAssign palDescPtr$, "!G_GFX_PALETTE_DESC$"

    ' Dereference to navigate through the descriptor to the actual string data payload
    palDataAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_READ_MEM, palDataAddr$ + ", " + palDescPtr$

    ' Offset = mask * 4 (32-bit RGBQUAD)
    colorOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_MUL, colorOffset$, fgMask$, "4"

    colorAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, colorAddr$, palDataAddr$, colorOffset$

    ' The palette natively stores B, G, R, 0 (RGBQUAD). We require COLORREF (0x00BBGGRR) for SetTextColor.
    ' We will extract each byte directly to reconstruct the variable perfectly in TIRA
    byteB$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, byteB$ + ", " + colorAddr$
    tiraOp TC_AND, byteB$, byteB$, "255"

    colorAddrG$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, colorAddrG$, colorAddr$, "1"
    byteG$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, byteG$ + ", " + colorAddrG$
    tiraOp TC_AND, byteG$, byteG$, "255"

    colorAddrR$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, colorAddrR$, colorAddr$, "2"
    byteR$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, byteR$ + ", " + colorAddrR$
    tiraOp TC_AND, byteR$, byteR$, "255"

    shiftG$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_SHL, shiftG$, byteG$, "8"

    shiftB$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_SHL, shiftB$, byteB$, "16"

    actualColor$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_ADD, actualColor$, byteR$, shiftG$
    tiraOp TC_ADD, actualColor$, actualColor$, shiftB$

    ' Write into the target tracking variable
    fgRgbPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, fgRgbPtr$, "!G_GFX_FG_VAL", ""

    tiraWriteMem fgRgbPtr$, actualColor$, "4"
  ELSE
    ' Console mode logic - combine attributes into (BG_MASK) OR (FG_MASK)

    ' FG_MASK = FG AND 15
    fgMask$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_AND, fgMask$, fgStr$, "15"

    ' BG_SHIFT = BG * 16 (equivalent to SHL 4)
    bgShift$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_MUL, bgShift$, bgStr$, "16"

    ' BG_MASK = BG_SHIFT AND 240
    bgMask$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_AND, bgMask$, bgShift$, "240"

    ' FINAL_ATTR = FG_MASK OR BG_MASK
    finalAttr$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_OR, finalAttr$, fgMask$, bgMask$

    ' Call GetStdHandle(-11)
    tiraCall "IAT_GETSTDHANDLE", 1, "-11"

    ' Retrieve the handle from RAX into a virtual register
    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_GET_RET, hndVar$

    ' Call SetConsoleTextAttribute
    tiraCall "IAT_SETCONSOLETEXTATTRIBUTE", 2, hndVar$ + ", " + finalAttr$
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_COLOR = 1

END FUNCTION ' parse_COLOR

''''''''''''''''''''''''
FUNCTION parse_COMMON (startIdx)

  DIM tempSuccess AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 2 THEN
    throwCompilerError "MALFORMED COMMON SHARED", ASIS, 0
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> TOK_SHARED THEN
    throwCompilerError "EXPECTED SHARED AFTER COMMON", ASIS, 0
    EXIT FUNCTION
  END IF

  tempSuccess = parse_GLOBAL_Core(startIdx + 2, endIdx)

  return2 endIdx
  parse_COMMON = tempSuccess

END FUNCTION ' parse_COMMON

''''''''''''''''''''''''
FUNCTION parse_COS$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM argFloat$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED COS", ASIS, 0
    parse_COS$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED COS", ASIS, 0
    parse_COS$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_COS$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_COS$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("COS", "_VAL")
  IF scratchName$ = "" THEN
    parse_COS$ = ""
    EXIT FUNCTION
  END IF

  ' Explicitly override the integer prefix rule to safely route as float
  ff = resolveSymbol(scratchName$)
  IF ff = 1 THEN symbols(returnedData2).DataType = TYPE_DOUBLE

  resVar$ = tiraDimVar$("T", TYPE_DOUBLE)

  ' Coerce the argument to a double for the external IAT function
  IF exprIs.DataType <> TYPE_DOUBLE THEN
    argFloat$ = tiraDimVar$("T", TYPE_DOUBLE)
    tiraAssign argFloat$, arg1$
    arg1$ = argFloat$
  END IF

  tiraCall "IAT_COS", 1, arg1$
  tiraNew TC_GET_RET, resVar$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_DOUBLE
  exprIs.IsTemp = 1
  parse_COS$ = scratchName$

END FUNCTION ' parse_COS$

''''''''''''''''''''''''
FUNCTION parse_DIM (startIdx)

  DIM endIdx AS LONG
  DIM tokIdx AS LONG
  DIM isShared AS LONG
  DIM arrSize1 AS LONG
  DIM arrSize2 AS LONG
  DIM isArray AS LONG
  DIM parenStart AS LONG
  DIM parenEnd AS LONG
  DIM dim1Start AS LONG
  DIM dim1End AS LONG
  DIM dim2Start AS LONG
  DIM dim2End AS LONG
  DIM hasComma AS LONG
  DIM commaIdx AS LONG
  DIM hasTo1 AS LONG
  DIM to1Idx AS LONG
  DIM hasTo2 AS LONG
  DIM to2Idx AS LONG
  DIM evalStart1 AS LONG
  DIM evalStart2 AS LONG
  DIM isNum AS LONG
  DIM i_check AS LONG
  DIM vIdx AS LONG
  DIM fixedLen AS LONG
  DIM dtMapped AS LONG
  DIM axIdx AS LONG
  DIM ayIdx AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM totalElems AS LONG
  DIM allocSize AS LONG
  DIM baseArrayName$
  DIM typeData AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tokIdx = startIdx + 1
  isShared = 0

  IF tokIdx <= endIdx THEN
    IF lineTokenVals(tokIdx) = TOK_SHARED THEN
      isShared = 1
      tokIdx = tokIdx + 1
    END IF
  END IF

  IF endIdx < tokIdx THEN
    throwCompilerError "MALFORMED DIM", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  DO WHILE tokIdx <= endIdx
    aTok$ = lineTokens$(tokIdx)
    IF lineTokenVals(tokIdx) <> 0 THEN
      throwCompilerErrorAndCancelTira "EXPECTED IDENTIFIER", ASIS, 0
      EXIT FUNCTION
    END IF

    tokIdx = tokIdx + 1

    arrSize1 = 1
    arrSize2 = 0
    isArray = 0

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
        isArray = 1
        parenStart = tokIdx

        ff = findMatchingParen(parenStart, endIdx)
        IF ff = 0 THEN
          throwCompilerErrorAndCancelTira "MALFORMED ARRAY DIMENSION", ASIS, 0
          EXIT FUNCTION
        END IF
        parenEnd = returnedData2

        tokIdx = parenStart + 1

        commaIdx = findComma(tokIdx, parenEnd - 1)
        IF commaIdx > 0 THEN hasComma = 1 ELSE hasComma = 0

        '''' Dimension 1
        dim1Start = tokIdx
        IF hasComma = 1 THEN dim1End = commaIdx - 1 ELSE dim1End = parenEnd - 1

        hasTo1 = 0
        to1Idx = 0
        ff = findNextTokenAtDepth0(dim1Start, dim1End, TOK_TO)
        IF ff = 1 THEN
          hasTo1 = 1
          to1Idx = returnedData2
        END IF

        evalStart1 = dim1Start
        IF hasTo1 = 1 THEN evalStart1 = to1Idx + 1

        IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
        dynAxVar$ = tiraParseExpressionInt$(evalStart1, dim1End, ALIM, "ARRAY DIM MUST BE NUMERIC")
        IF dynAxVar$ = "" THEN
          tira_Cancel
          EXIT FUNCTION
        END IF

        dynAxVarTotal$ = tiraDimVar$("T", TYPE_LONG)
        tiraOp TC_ADD, dynAxVarTotal$, dynAxVar$, "1"

        sizeTok$ = ""
        FOR ii = evalStart1 TO dim1End
          sizeTok$ = sizeTok$ + retTokenText$(lineTokens$(ii))
        NEXT
        sizeTok$ = evalMathConst$(sizeTok$)

        isNum = 1
        FOR i_check = 1 TO LEN(sizeTok$)
          chCheck$ = MID$(sizeTok$, i_check, 1)
          IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN
            isNum = 0
            EXIT FOR
          END IF
        NEXT
        IF isNum = 0 OR sizeTok$ = "" THEN
          arrSize1 = 0
          isArray = 2
        ELSE
          arrSize1 = VAL(sizeTok$) + 1
          IF defaultArrayDynamic = 1 THEN isArray = 2
        END IF

        '''' Dimension 2
        arrSize2 = 0
        dynAyVarTotal$ = tiraDimVar$("T", TYPE_LONG)
        tiraAssign dynAyVarTotal$, "0"

        IF hasComma = 1 THEN
          dim2Start = commaIdx + 1
          dim2End = parenEnd - 1

          hasTo2 = 0
          to2Idx = 0
          ff = findNextTokenAtDepth0(dim2Start, dim2End, TOK_TO)
          IF ff = 1 THEN
            hasTo2 = 1
            to2Idx = returnedData2
          END IF

          evalStart2 = dim2Start
          IF hasTo2 = 1 THEN evalStart2 = to2Idx + 1

          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          dynAyVar$ = tiraParseExpressionInt$(evalStart2, dim2End, ALIM, "ARRAY DIM MUST BE NUMERIC")
          IF dynAyVar$ = "" THEN
            tira_Cancel
            EXIT FUNCTION
          END IF

          tiraOp TC_ADD, dynAyVarTotal$, dynAyVar$, "1"

          sizeTok2$ = ""
          FOR ii = evalStart2 TO dim2End
            sizeTok2$ = sizeTok2$ + retTokenText$(lineTokens$(ii))
          NEXT
          sizeTok2$ = evalMathConst$(sizeTok2$)

          isNum = 1
          FOR i_check = 1 TO LEN(sizeTok2$)
            chCheck$ = MID$(sizeTok2$, i_check, 1)
            IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN
              isNum = 0
              EXIT FOR
            END IF
          NEXT
          IF isNum = 0 OR sizeTok2$ = "" THEN
            arrSize2 = 0
            isArray = 2
          ELSE
            arrSize2 = VAL(sizeTok2$) + 1
            IF defaultArrayDynamic = 1 THEN isArray = 2
          END IF
        END IF

        tokIdx = parenEnd + 1
      END IF
    END IF

    vName$ = UCASE$(aTok$)
    ff = resolveSymbol(vName$)
    IF ff = 0 THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
    vIdx = returnedData2

    IF symbols(vIdx).IsArray = 1 THEN
      IF isDummyPass = 1 THEN
        throwCompilerErrorAndCancelTira "ARRAY ALREADY DIMMED", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF

    symbols(vIdx).IsArray = isArray
    symbols(vIdx).IsExplicit = 1
    IF isShared = 1 THEN symbols(vIdx).IsShared = 1

    IF arrSize2 > 0 THEN
      symbols(vIdx).Size = arrSize1 * arrSize2
      symbols(vIdx).Size2 = arrSize2
    ELSE
      symbols(vIdx).Size = arrSize1
      symbols(vIdx).Size2 = 0
    END IF

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = TOK_AS THEN
        tokIdx = tokIdx + 1
        tokIdx = parseTypeClause(tokIdx, endIdx)
        dtMapped = returnedData2
        typeData = returnedData3

        IF dtMapped = TYPE_UNDEFINED THEN
          tira_Cancel
          EXIT FUNCTION
        END IF

        symbols(vIdx).DataType = dtMapped
        IF dtMapped = TYPE_UDT THEN
          symbols(vIdx).UDTIndex = typeData
        ELSE
          IF dtMapped = TYPE_STRING THEN
            fixedLen = typeData
            IF fixedLen > 0 THEN
              symbols(vIdx).FixedStrLen = fixedLen
              strVarData$(vIdx) = SPACE$(fixedLen)
            END IF
          END IF
        END IF
      END IF
    END IF

    IF isArray > 0 THEN
      baseArrayName$ = RTRIM$(symbols(vIdx).RecordName)
      ff = resolveSymbol("!G_SYS_" + baseArrayName$ + "_AX_VAL")
      IF ff = 1 THEN axIdx = returnedData2
      ff = resolveSymbol("!G_SYS_" + baseArrayName$ + "_AY_VAL")
      IF ff = 1 THEN ayIdx = returnedData2

      ' Assigning dynamic tracking variables via TIRA protects sizing natively
      tiraAssign RTRIM$(symbols(axIdx).RecordName), dynAxVarTotal$
      tiraAssign RTRIM$(symbols(ayIdx).RecordName), dynAyVarTotal$

      IF isArray = 2 THEN
        dt = symbols(vIdx).DataType
        elemSize = 8

        SELECT CASE dt

          CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
          CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
          CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
          CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
          CASE TYPE_STRING
            fixedLen = retFixedStringLength(vIdx)
            IF fixedLen > 0 THEN
              elemSize = fixedLen
            ELSE
              elemSize = 8
            END IF
          CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize

        END SELECT ' dt

        elemSizeStr$ = tiraDimVar$("T", TYPE_LONG)
        tiraAssign elemSizeStr$, LTRIM$(STR$(elemSize))

        totalElems$ = tiraDimVar$("T", TYPE_LONG)
        tiraAssign totalElems$, dynAxVarTotal$

        skipYMul$ = tiraLabelCreateNew$("SKIP_YMUL")
        tiraJmpCond "JLE", dynAyVarTotal$, "0", skipYMul$
        tiraOp TC_MUL, totalElems$, totalElems$, dynAyVarTotal$
        tiraLabel skipYMul$

        allocSize$ = tiraDimVar$("T", TYPE_LONG)
        tiraOp TC_MUL, allocSize$, totalElems$, elemSizeStr$

        tiraScheduleArrayFree vIdx

        tiraCall "IAT_HEAPALLOC", 3, "!G_MEM_PROCESS_HEAP_PTR, 8, " + allocSize$
        arrPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
        tiraNew TC_GET_RET, arrPtr$
        tiraAssign baseArrayName$, arrPtr$
      END IF
    END IF

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
        tokIdx = tokIdx + 1
      ELSE
        throwCompilerErrorAndCancelTira "UNEXPECTED TOKEN AFTER DIM", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF
  LOOP

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_DIM = 1

END FUNCTION ' parse_DIM

''''''''''''''''''''''''
FUNCTION parse_DISPLAY (startIdx)

  parse_DISPLAY = parse_DISPLAY_Core(startIdx, 0)

END FUNCTION ' parse_DISPLAY

''''''''''''''''''''''''
FUNCTION parse_DISPLAYI (startIdx)

  parse_DISPLAYI = parse_DISPLAY_Core(startIdx, 1)

END FUNCTION ' parse_DISPLAYI

''''''''''''''''''''''''
FUNCTION parse_DISPLAY_Core (startIdx, isDisplayI)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF isDisplayI = 1 THEN cmdName$ = "_DISPLAYI" ELSE cmdName$ = "_DISPLAY"

  IF compileHasGraphics = 0 THEN
    throwCompilerError cmdName$ + " REQUIRES #GRAPHICS", ASIS, 0
    EXIT FUNCTION
  END IF

  ff = verifyNoExtraTokens(endIdx, startIdx, cmdName$)
  IF ff = 0 THEN EXIT FUNCTION

  tira_Start

  tiraAssign "!G_GFX_AUTODISPLAY_FLAG", "0"

  IF isDisplayI = 0 THEN
    tiraCall "RT_SWAP_BUFFERS", 0, ""
  ELSE
    tiraInjectPendingDisplayFlush
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_DISPLAY_Core = 1

END FUNCTION ' parse_DISPLAY_Core

''''''''''''''''''''''''
FUNCTION parse_DO (startIdx)

  DIM endIdx AS LONG
  DIM hasCond AS LONG
  DIM tVal AS LONG
  DIM loopID AS LONG

  ' Generate a globally unique ID for this loop structure
  loopID = t.TiraVarCounter
  t.TiraVarCounter = t.TiraVarCounter + 1

  topLbl$ = "@DO_TOP_" + cTrNum$(loopID)
  doneLbl$ = "@DO_DONE_" + cTrNum$(loopID)

  ' Anchor the top of the loop in the TIRA symbol table
  tira_Start
  tiraLabel topLbl$
  tira_EndAndProcess

  hoistIntrinsics
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT FUNCTION

  ' Restore the expected symbol type to a clean slate
  expectedSymType = TYPE_ANY

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  hasCond = 0

  IF endIdx > startIdx THEN
    tVal = lineTokenVals(startIdx + 1)
    IF tVal = TOK_UNTIL OR tVal = TOK_WHILE THEN
      hasCond = 1
    ELSE
      throwCompilerError "EXPECTED UNTIL OR WHILE", ASIS, 0
      EXIT FUNCTION
    END IF
  END IF

  tira_Start

  IF hasCond = 1 THEN
    exprVar$ = tiraParseExpressionNumeric$(startIdx + 2, endIdx, ALIM, "TYPE MISMATCH IN CONDITION")
    IF exprVar$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    IF tVal = TOK_UNTIL THEN
      tiraJmpCond "JNE", exprVar$, "0", doneLbl$
    ELSE
      tiraJmpCond "JE", exprVar$, "0", doneLbl$
    END IF
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_DO
  ctrls(ctrlCount).Patch1 = loopID ' Save the Loop ID for parse_LOOP and parse_EXIT
  ctrls(ctrlCount).Patch2 = 0 ' Unused for loop structures as TIRA labels manage exit jumps
  ctrlCount = ctrlCount + 1

  return2 endIdx
  parse_DO = 1

END FUNCTION ' parse_DO

''''''''''''''''''''''''
FUNCTION parse_END (startIdx)

  DIM endIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  isBlockEnd = 0
  IF endIdx > startIdx THEN
    tok2 = lineTokenVals(startIdx + 1)
    IF tok2 = TOK_SUB OR tok2 = TOK_FUNCTION THEN isBlockEnd = 1
    IF tok2 = TOK_IF THEN isBlockEnd = 1
    IF tok2 = TOK_SELECT THEN isBlockEnd = 1
  END IF

  IF isBlockEnd = 1 THEN
    tok2 = lineTokenVals(startIdx + 1)
    SELECT CASE tok2

      CASE TOK_SUB, TOK_FUNCTION
        IF tok2 = TOK_SUB AND insideSub <> 1 THEN
          throwCompilerError "END SUB WITHOUT SUB", ASIS, 0
          EXIT FUNCTION
        END IF
        IF tok2 = TOK_FUNCTION AND insideSub <> 2 THEN
          throwCompilerError "FUNCTION END WITHOUT FUNCTION", ASIS, 0
          EXIT FUNCTION
        END IF

        ' Resolve all early EXIT SUB / EXIT FUNCTION jumps to land here via TIRA labels
        tira_Start
        tiraLabel "@END_ROUTINE_" + currentSubName$
        tiraScheduleGC

        ' Restore stack alignment, pop ABI non-volatile registers, and return
        tiraScheduleSubEpilogue

        ' Land the jump over the SUB/FUNCTION
        tiraLabel "@SKIP_ROUTINE_" + currentSubName$
        tira_EndAndProcess

        currentScopeID = 0
        insideSub = 0
        currentSubName$ = ""
        stack.currentStackOffset = 0
        ff = updateStackAlignment

        return2 endIdx
        parse_END = 1
        EXIT FUNCTION

      CASE TOK_IF
        IF ctrlCount = 0 THEN
          throwCompilerError "END IF WITHOUT IF", ASIS, 0
          EXIT FUNCTION
        END IF

        ctrlCount = ctrlCount - 1

        IF ctrls(ctrlCount).Type = CTRL_IF OR ctrls(ctrlCount).Type = CTRL_ELSE THEN
          ifID = ctrls(ctrlCount).Patch1
          falseLbl$ = "@IF_FALSE_" + cTrNum$(ifID)
          endLbl$ = "@IF_END_" + cTrNum$(ifID)

          tira_Start

          ' If we never saw an ELSE statement, the FALSE condition must skip to here
          IF ctrls(ctrlCount).Type = CTRL_IF THEN
            tiraLabel falseLbl$
          END IF

          ' Any executed blocks will jump directly here to bypass trailing conditions
          tiraLabel endLbl$

          tira_EndAndProcess
        ELSE
          throwCompilerError "END IF MISMATCH", ASIS, 0
          EXIT FUNCTION
        END IF

        return2 endIdx
        parse_END = 1
        EXIT FUNCTION

      CASE TOK_SELECT
        IF ctrlCount = 0 THEN
          throwCompilerError "END SELECT WITHOUT SELECT", ASIS, 0
          EXIT FUNCTION
        END IF

        ctrlCount = ctrlCount - 1

        IF ctrls(ctrlCount).Type = CTRL_SELECT THEN
          selID = ctrls(ctrlCount).Patch1
          caseID = ctrls(ctrlCount).SelectCaseSeen

          tira_Start

          IF caseID > 0 THEN
            ' The final case's conditions would skip to right here if they all failed
            prevNextLbl$ = "@SEL_NEXT_" + cTrNum$(selID) + "_" + cTrNum$(caseID - 1)
            tiraLabel prevNextLbl$
          END IF

          endSelLbl$ = "@SEL_END_" + cTrNum$(selID)
          tiraLabel endSelLbl$

          tira_EndAndProcess

        ELSE
          throwCompilerError "END SELECT MISMATCH", ASIS, 0
          EXIT FUNCTION
        END IF

        return2 endIdx
        parse_END = 1
        EXIT FUNCTION

    END SELECT ' tok2
  END IF

  ' Standalone END with optional return code
  tira_Start

  IF endIdx > startIdx THEN
    exprVar$ = tiraParseExpressionInt$(startIdx + 1, endIdx, ALIM, "END REQUIRES NUMERIC")
    IF exprVar$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    ff = resolveSymbol("!G_SYS_EXIT_VAL")
    IF ff = 1 THEN
      vIdxExit = returnedData2
      tiraAssign "!G_SYS_EXIT_VAL", exprVar$
    END IF
  END IF

  ' Jump to the end of the program
  tiraJmp "@END_PROGRAM"

  tira_EndAndProcess

  return2 endIdx
  parse_END = 1

END FUNCTION ' parse_END

''''''''''''''''''''''''
FUNCTION parse_EXIT (startIdx)

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM isCtrlFound AS LONG
  DIM foundCtrlIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "EXPECTED SUB OR FUNCTION", ASIS, 0
    EXIT FUNCTION
  END IF

  tok2 = lineTokenVals(startIdx + 1)
  SELECT CASE tok2

    CASE TOK_SUB, TOK_FUNCTION
      IF tok2 = TOK_SUB AND insideSub <> 1 THEN
        throwCompilerError "EXIT SUB OUTSIDE SUB", ASIS, 0
        EXIT FUNCTION
      END IF
      IF tok2 = TOK_FUNCTION AND insideSub <> 2 THEN
        throwCompilerError "EXIT FUNCTION OUTSIDE FUNCTION", ASIS, 0
        EXIT FUNCTION
      END IF

      ' Route control flow to the subroutine epilogue via a forward jump
      ' This jump targets the end routine label defined and placed by parse_END
      ' This ensures early exits execute unified garbage collection and stack restoration

      ff = resolveSymbol(currentSubName$)
      IF ff = 1 THEN
        vIdx = returnedData2
        subIdx = symbols(vIdx).SubIndex
        IF subIdx > 0 THEN
          tira_Start
          tiraScheduleHeapReset
          tiraJmp "@END_ROUTINE_" + currentSubName$
          tira_EndAndProcess
        END IF
      END IF

    CASE TOK_CASE, TOK_SELECT
      isCtrlFound = 0
      foundCtrlIdx = 0
      FOR cIdx = ctrlCount - 1 TO 0 STEP -1
        IF ctrls(cIdx).Type = CTRL_SELECT THEN
          foundCtrlIdx = cIdx
          isCtrlFound = 1
          EXIT FOR
        END IF
      NEXT

      IF isCtrlFound = 0 THEN
        throwCompilerError "EXIT CASE OUTSIDE SELECT", ASIS, 0
        EXIT FUNCTION
      END IF

      selID = ctrls(foundCtrlIdx).Patch1

      tira_Start
      tiraScheduleHeapReset
      tiraJmp "@SEL_END_" + cTrNum$(selID)
      tira_EndAndProcess

    CASE TOK_DO
      isCtrlFound = 0
      foundCtrlIdx = 0
      FOR cIdx = ctrlCount - 1 TO 0 STEP -1
        IF ctrls(cIdx).Type = CTRL_DO THEN
          foundCtrlIdx = cIdx
          isCtrlFound = 1
          EXIT FOR
        END IF
      NEXT

      IF isCtrlFound = 0 THEN
        throwCompilerError "EXIT DO OUTSIDE DO LOOP", ASIS, 0
        EXIT FUNCTION
      END IF

      loopID = ctrls(foundCtrlIdx).Patch1

      ' Native TIRA integration completely negates the need to walk raw machine code patches
      tira_Start
      tiraScheduleHeapReset
      tiraJmp "@DO_DONE_" + cTrNum$(loopID)
      tira_EndAndProcess

    CASE TOK_FOR
      isCtrlFound = 0
      foundCtrlIdx = 0
      FOR cIdx = ctrlCount - 1 TO 0 STEP -1
        IF ctrls(cIdx).Type = CTRL_FOR THEN
          foundCtrlIdx = cIdx
          isCtrlFound = 1
          EXIT FOR
        END IF
      NEXT

      IF isCtrlFound = 0 THEN
        throwCompilerError "EXIT FOR OUTSIDE FOR LOOP", ASIS, 0
        EXIT FUNCTION
      END IF

      loopID = ctrls(foundCtrlIdx).Patch1

      ' Native TIRA integration handles the forward jump via the symbol table
      tira_Start
      tiraScheduleHeapReset
      tiraJmp "@FOR_DONE_" + cTrNum$(loopID)
      tira_EndAndProcess

    CASE TOK_WHILE
      isCtrlFound = 0
      foundCtrlIdx = 0
      FOR cIdx = ctrlCount - 1 TO 0 STEP -1
        IF ctrls(cIdx).Type = CTRL_WHILE THEN
          foundCtrlIdx = cIdx
          isCtrlFound = 1
          EXIT FOR
        END IF
      NEXT

      IF isCtrlFound = 0 THEN
        throwCompilerError "EXIT WHILE OUTSIDE WHILE LOOP", ASIS, 0
        EXIT FUNCTION
      END IF

      loopID = ctrls(foundCtrlIdx).Patch1

      tira_Start
      tiraScheduleHeapReset
      tiraJmp "@WHILE_DONE_" + cTrNum$(loopID)
      tira_EndAndProcess

    CASE ELSE
      throwCompilerError "UNRECOGNIZED EXIT", ASIS, 0
      EXIT FUNCTION

  END SELECT ' tok2

  return2 endIdx
  parse_EXIT = 1

END FUNCTION ' parse_EXIT

''''''''''''''''''''''''
FUNCTION parse_FOR (startIdx)

  DIM endIdx AS LONG
  DIM vIdx AS LONG
  DIM vDataType AS LONG
  DIM hasTo AS LONG
  DIM toIdx AS LONG
  DIM hasStep AS LONG
  DIM stepIdx AS LONG
  DIM loopID AS LONG
  DIM endExprEnd AS LONG
  DIM endVarIdx AS LONG
  DIM stepVarIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 3 THEN
    throwCompilerError "MALFORMED FOR", ASIS, 0
    EXIT FUNCTION
  END IF

  vTok$ = lineTokens$(startIdx + 1)
  IF lineTokenVals(startIdx + 1) <> 0 OR RIGHT$(vTok$, 1) = "$" THEN
    throwCompilerError "FOR NEEDS NUMERIC VAR", ASIS, 0
    EXIT FUNCTION
  END IF

  vName$ = UCASE$(vTok$)
  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  ff = resolveSymbol(vName$)
  IF ff = 0 THEN EXIT FUNCTION
  vIdx = returnedData2
  vDataType = returnedData3

  IF lineTokenVals(startIdx + 2) <> 256 + ASC("=") THEN
    throwCompilerError "FOR MISSING =", ASIS, 0
    EXIT FUNCTION
  END IF

  hasTo = 0
  toIdx = 0
  hasStep = 0
  stepIdx = 0

  ff = findNextTokenAtDepth0(startIdx + 3, endIdx, TOK_TO)
  IF ff = 1 THEN
    hasTo = 1
    toIdx = returnedData2
  END IF

  ff = findNextTokenAtDepth0(startIdx + 3, endIdx, TOK_STEP)
  IF ff = 1 THEN
    hasStep = 1
    stepIdx = returnedData2
  END IF

  IF hasTo = 0 THEN
    throwCompilerError "FOR MISSING TO", ASIS, 0
    EXIT FUNCTION
  END IF

  IF toIdx <= startIdx + 2 THEN
    throwCompilerError "FOR MISSING START EXPR", ASIS, 0
    EXIT FUNCTION
  END IF

  IF hasStep = 1 THEN
    IF stepIdx <= toIdx + 1 THEN
      throwCompilerError "FOR MISSING END EXPR", ASIS, 0
      EXIT FUNCTION
    END IF
    IF stepIdx = endIdx THEN
      throwCompilerError "FOR MISSING STEP EXPR", ASIS, 0
      EXIT FUNCTION
    END IF
  ELSE
    IF toIdx = endIdx THEN
      throwCompilerError "FOR MISSING END EXPR", ASIS, 0
      EXIT FUNCTION
    END IF
  END IF

  ' Generate a globally unique ID for this loop structure
  loopID = t.TiraVarCounter
  t.TiraVarCounter = t.TiraVarCounter + 1

  tira_Start

  '''' Evaluate Start Value
  IF compileClassicMode = 1 THEN expectedSymType = vDataType
  startVar$ = tiraParseExpressionNumeric$(startIdx + 3, toIdx - 1, 0, "FOR NEEDS NUMERIC")
  IF startVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  endExprEnd = endIdx
  IF hasStep = 1 THEN endExprEnd = stepIdx - 1

  endName$ = "!G_SYS_FOR_END_" + cTrNum$(loopID) + "_VAL"
  ff = resolveSymbol(endName$)
  IF ff = 0 THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  endVarIdx = returnedData2
  symbols(endVarIdx).DataType = vDataType

  '''' Evaluate End Value
  IF compileClassicMode = 1 THEN expectedSymType = vDataType
  endVar$ = tiraParseExpressionNumeric$(toIdx + 1, endExprEnd, 0, "FOR NEEDS NUMERIC")
  IF endVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  stepName$ = "!G_SYS_FOR_STEP_" + cTrNum$(loopID) + "_VAL"
  ff = resolveSymbol(stepName$)
  IF ff = 0 THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  stepVarIdx = returnedData2
  symbols(stepVarIdx).DataType = vDataType

  '''' Evaluate Step Value
  IF hasStep = 1 THEN
    IF compileClassicMode = 1 THEN expectedSymType = vDataType
    stepVar$ = tiraParseExpressionNumeric$(stepIdx + 1, endIdx, 0, "FOR NEEDS NUMERIC")
    IF stepVar$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
  ELSE
    stepVar$ = "1"
  END IF

  vNameTira$ = RTRIM$(symbols(vIdx).RecordName)

  tiraAssign vNameTira$, startVar$
  tiraAssign endName$, endVar$
  tiraAssign stepName$, stepVar$

  lblTop$ = "@FOR_TOP_" + cTrNum$(loopID)
  lblCond$ = "@FOR_COND_" + cTrNum$(loopID)

  tiraJmp lblCond$
  tiraLabel lblTop$
  tiraScheduleHeapReset

  tira_EndAndProcess

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_FOR
  ctrls(ctrlCount).ForVarIdx = vIdx
  ctrls(ctrlCount).Patch1 = loopID ' Save the Loop ID for parse_NEXT and parse_EXIT
  ctrls(ctrlCount).Patch2 = 0 ' Unused
  ctrlCount = ctrlCount + 1

  return2 endIdx
  parse_FOR = 1

END FUNCTION ' parse_FOR

''''''''''''''''''''''''
FUNCTION parse_FULLSCREEN (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF compileHasGraphics = 0 THEN
    throwCompilerError "_FULLSCREEN REQUIRES #GRAPHICS", ASIS, 0
    EXIT FUNCTION
  END IF

  ff = verifyNoExtraTokens(endIdx, startIdx, "_FULLSCREEN")
  IF ff = 0 THEN EXIT FUNCTION

  tira_Start

  tiraCall "RT_FULLSCREEN", 0, ""
  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_FULLSCREEN = 1

END FUNCTION ' parse_FULLSCREEN

''''''''''''''''''''''''
FUNCTION parse_GET (startIdx)

  DIM dashIdx AS LONG
  DIM isFileIO AS LONG
  DIM cComma AS LONG
  DIM cStart1 AS LONG
  DIM cEnd1 AS LONG
  DIM commaIdx AS LONG
  DIM cComma2 AS LONG
  DIM cStart2 AS LONG
  DIM cEnd2 AS LONG
  DIM tokIdx AS LONG
  DIM closeParen AS LONG
  DIM arrComma AS LONG
  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM statElems AS LONG
  DIM fixedLen AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  dashIdx = 0
  ff = findNextTokenAtDepth0(startIdx + 1, endIdx, 256 + ASC("-"))
  IF ff = 1 THEN
    dashIdx = returnedData2
  END IF

  isFileIO = 0
  IF dashIdx = 0 THEN
    isFileIO = 1
  END IF

  IF isFileIO = 1 THEN
    parse_GET = parse_GET_File(startIdx, endIdx)
    EXIT FUNCTION
  END IF

  IF compileHasGraphics = 0 THEN
    throwCompilerError "GRAPHICS GET REQUIRES #GRAPHICS", ASIS, 0
    EXIT FUNCTION
  END IF

  cComma = retCoordinateBoundaries(startIdx + 1, dashIdx - 1)
  IF cComma = 0 THEN
    throwCompilerError "GET MISSING X1, Y1", ASIS, 0
    EXIT FUNCTION
  END IF
  cStart1 = returnedData2
  cEnd1 = returnedData3

  tira_Start

  x1$ = tiraParseExpressionInt$(cStart1, cComma - 1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF x1$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  y1$ = tiraParseExpressionInt$(cComma + 1, cEnd1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF y1$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  commaIdx = findComma(dashIdx + 1, endIdx)

  IF commaIdx = 0 THEN
    throwCompilerError "GET MISSING ARRAY VARIABLE", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF

  cComma2 = retCoordinateBoundaries(dashIdx + 1, commaIdx - 1)
  IF cComma2 = 0 THEN
    throwCompilerError "GET MISSING X2, Y2", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF
  cStart2 = returnedData2
  cEnd2 = returnedData3

  x2$ = tiraParseExpressionInt$(cStart2, cComma2 - 1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF x2$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  y2$ = tiraParseExpressionInt$(cComma2 + 1, cEnd2, ALIM, "COORDINATE MUST BE NUMERIC")
  IF y2$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  tokIdx = commaIdx + 1
  vTok$ = lineTokens$(tokIdx)
  vName$ = UCASE$(vTok$)
  ff = resolveSymbol(vName$)
  IF ff = 0 THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  vIdx = returnedData2

  IF symbols(vIdx).IsArray = 0 THEN
    throwCompilerError "GET TARGET MUST BE AN ARRAY", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF

  arrX$ = ""
  arrY$ = ""

  tokIdx = tokIdx + 1
  IF tokIdx <= endIdx THEN
    IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
      ff = findMatchingParen(tokIdx, endIdx)
      IF ff = 1 THEN
        closeParen = returnedData2
        arrComma = findComma(tokIdx + 1, closeParen - 1)
        IF arrComma > 0 THEN
          arrX$ = tiraParseExpressionInt$(tokIdx + 1, arrComma - 1, 0, "INDEX MUST BE NUMERIC")
          arrY$ = tiraParseExpressionInt$(arrComma + 1, closeParen - 1, 0, "INDEX MUST BE NUMERIC")
        ELSE
          arrX$ = tiraParseExpressionInt$(tokIdx + 1, closeParen - 1, 0, "INDEX MUST BE NUMERIC")
        END IF
      END IF
    END IF
  END IF

  ptr$ = tiraFrontendCalcAddress$(vName$, arrX$, arrY$, 0)
  IF ptr$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  actualName$ = RTRIM$(symbols(vIdx).RecordName)
  dt = symbols(vIdx).DataType
  elemSize = 8

  SELECT CASE dt
    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
    CASE TYPE_STRING
      fixedLen = retFixedStringLength(vIdx)
      IF fixedLen > 0 THEN elemSize = fixedLen ELSE elemSize = 8
    CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
  END SELECT

  totalElems$ = tiraDimVar$("T", TYPE_LONG)

  IF symbols(vIdx).IsArray = 1 THEN
    statElems = symbols(vIdx).Size
    IF symbols(vIdx).Size2 > 0 THEN statElems = statElems * symbols(vIdx).Size2
    tiraAssign totalElems$, LTRIM$(STR$(statElems))
  ELSE
    tiraAssign totalElems$, "!G_SYS_" + actualName$ + "_AX_VAL"
    IF symbols(vIdx).Size2 > 0 THEN
      tiraOp TC_MUL, totalElems$, totalElems$, "!G_SYS_" + actualName$ + "_AY_VAL"
    END IF
  END IF

  safeElems$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_CAST, safeElems$, totalElems$, LTRIM$(STR$(TYPE_INTEGER64))

  byteSize$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_MUL, byteSize$, safeElems$, LTRIM$(RTRIM$(STR$(elemSize)))

  baseAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  IF symbols(vIdx).IsArray = 2 THEN
    tiraNew TC_READ_MEM, baseAddr$ + ", " + actualName$
  ELSE
    tiraOp TC_ADDRESS_OF, baseAddr$, actualName$, ""
  END IF

  endPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, endPtr$, baseAddr$, byteSize$

  tiraCall "RT_GET", 6, x1$ + ", " + y1$ + ", " + x2$ + ", " + y2$ + ", " + ptr$ + ", " + endPtr$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_GET = 1

END FUNCTION ' parse_GET

''''''''''''''''''''''''
FUNCTION parse_GET_File (startIdx, endIdx)

  DIM comma1 AS LONG
  DIM comma2 AS LONG
  DIM targetStart AS LONG
  DIM closeParen AS LONG
  DIM arrComma AS LONG
  DIM tokIdx AS LONG
  DIM vTok$, vName$
  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM fixedLen AS LONG

  DIM hasArrayIndices AS LONG

  tokIdx = startIdx + 1
  IF lineTokens$(tokIdx) = "#" THEN
    tokIdx = tokIdx + 1
  ELSE
    IF LEFT$(lineTokens$(tokIdx), 1) = "#" THEN
      lineTokens$(tokIdx) = MID$(lineTokens$(tokIdx), 2)
    END IF
  END IF

  comma1 = findComma(tokIdx, endIdx)
  IF comma1 = 0 THEN
    throwCompilerError "GET MISSING COMMA", ASIS, 0
    EXIT FUNCTION
  END IF

  comma2 = findComma(comma1 + 1, endIdx)
  IF comma2 = 0 THEN
    targetStart = comma1 + 1
  ELSE
    targetStart = comma2 + 1
  END IF

  IF targetStart > endIdx THEN
    throwCompilerError "GET MISSING TARGET VARIABLE", ASIS, 0
    EXIT FUNCTION
  END IF

  vTok$ = lineTokens$(targetStart)
  vName$ = UCASE$(vTok$)
  ff = resolveSymbol(vName$)
  IF ff = 0 THEN EXIT FUNCTION
  vIdx = returnedData2

  tira_Start

  fileNumVar$ = tiraParseExpressionInt$(tokIdx, comma1 - 1, ALIM, "FILE NUM MUST BE NUMERIC")
  IF fileNumVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  xVar$ = ""
  yVar$ = ""
  hasArrayIndices = 0

  IF targetStart < endIdx THEN
    IF lineTokenVals(targetStart + 1) = 256 + ASC("(") THEN
      hasArrayIndices = 1
      ff = findMatchingParen(targetStart + 1, endIdx)
      IF ff = 1 THEN
        closeParen = returnedData2
        arrComma = findComma(targetStart + 2, closeParen - 1)
        IF arrComma > 0 THEN
          xVar$ = tiraParseExpressionInt$(targetStart + 2, arrComma - 1, ALIM, "INDEX MUST BE NUMERIC")
          yVar$ = tiraParseExpressionInt$(arrComma + 1, closeParen - 1, ALIM, "INDEX MUST BE NUMERIC")
        ELSE
          xVar$ = tiraParseExpressionInt$(targetStart + 2, closeParen - 1, ALIM, "INDEX MUST BE NUMERIC")
        END IF

        IF xVar$ = "" OR (arrComma > 0 AND yVar$ = "") THEN
          tira_Cancel
          EXIT FUNCTION
        END IF
      ELSE
        throwCompilerError "MISSING )", ASIS, 0
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF
  END IF

  baseArr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, baseArr$, "!G_LAYOUT_FILE_HANDLES_ARR", ""

  slotAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraLeaSIB slotAddr$, baseArr$, fileNumVar$, "8"

  handleVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, handleVar$ + ", " + slotAddr$

  skipFileIOLbl$ = tiraLabelCreateNew$("SKIP_FILE_IO")

  tiraJmpCond "JE", handleVar$, "0", skipFileIOLbl$
  tiraJmpCond "JE", handleVar$, "-1", skipFileIOLbl$

  ptr$ = tiraFrontendCalcAddress$(vName$, xVar$, yVar$, 0)
  IF ptr$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  dt = symbols(vIdx).DataType
  elemSize = 8

  SELECT CASE dt

    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
    CASE TYPE_STRING:
      fixedLen = retFixedStringLength(vIdx)
      IF fixedLen > 0 THEN elemSize = fixedLen ELSE elemSize = 8
    CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize

  END SELECT ' dt

  dataSize$ = tiraDimVar$("T", TYPE_LONG)
  dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)

  IF dt = TYPE_STRING AND fixedLen = 0 THEN
    descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)

    IF symbols(vIdx).IsArray > 0 THEN
      tiraNew TC_READ_MEM, descPtr$ + ", " + ptr$
    ELSE
      tiraAssign descPtr$, ptr$
    END IF

    tiraJmpCond "JE", descPtr$, "0", skipFileIOLbl$

    tiraAssign dataSize$, tiraGetStringLen$(descPtr$)
    tiraAssign dataPtr$, tiraGetStringData$(descPtr$)

    tiraJmpCond "JLE", dataSize$, "0", skipFileIOLbl$
    tiraJmpCond "JE", dataPtr$, "0", skipFileIOLbl$

  ELSE
    IF dt = TYPE_STRING AND fixedLen > 0 THEN
      tiraAssign dataSize$, LTRIM$(STR$(fixedLen))

      IF symbols(vIdx).IsArray > 0 THEN
        tiraAssign dataPtr$, ptr$
      ELSE
        descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
        tiraAssign descPtr$, ptr$

        tiraJmpCond "JE", descPtr$, "0", skipFileIOLbl$

        tiraAssign dataPtr$, tiraGetStringData$(descPtr$)
        tiraJmpCond "JE", dataPtr$, "0", skipFileIOLbl$
      END IF
    ELSE
      tiraAssign dataSize$, LTRIM$(STR$(elemSize))
      tiraAssign dataPtr$, ptr$

      tiraJmpCond "JLE", dataSize$, "0", skipFileIOLbl$
    END IF
  END IF

  numWrt$ = tiraDimVar$("T", TYPE_LONG)
  numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

  tiraCall "IAT_READFILE", 5, handleVar$ + ", " + dataPtr$ + ", " + dataSize$ + ", " + numWrtPtr$ + ", 0"

  tiraLabel skipFileIOLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_GET_File = 1

END FUNCTION ' parse_GET_File

''''''''''''''''''''''''
FUNCTION parse_GLOBAL (startIdx)

  DIM tempSuccess AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "MALFORMED GLOBAL", ASIS, 0
    EXIT FUNCTION
  END IF

  tempSuccess = parse_GLOBAL_Core(startIdx + 1, endIdx)

  return2 endIdx
  parse_GLOBAL = tempSuccess

END FUNCTION ' parse_GLOBAL

''''''''''''''''''''''''
FUNCTION parse_GLOBAL_Core (startTokIdx, endIdx)

  ' Used by the synonym commands GLOBAL and COMMON SHARED

  DIM dtMapped AS LONG
  DIM fixedLen AS LONG
  DIM typeData AS LONG

  tokIdx = startTokIdx

  DO WHILE tokIdx <= endIdx
    vTok$ = lineTokens$(tokIdx)
    IF lineTokenVals(tokIdx) <> 0 THEN
      throwCompilerError "EXPECTED VARIABLE NAME", ASIS, 0
      EXIT FUNCTION
    END IF

    vName$ = UCASE$(vTok$)
    ff = resolveSymbol(vName$)
    IF ff = 0 THEN
      EXIT FUNCTION
    END IF
    vIdx = returnedData2

    symbols(vIdx).IsShared = 1
    symbols(vIdx).IsExplicit = 1

    tokIdx = tokIdx + 1

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = TOK_AS THEN
        tokIdx = tokIdx + 1
        tokIdx = parseTypeClause(tokIdx, endIdx)
        dtMapped = returnedData2
        typeData = returnedData3

        IF dtMapped = TYPE_UNDEFINED THEN EXIT FUNCTION

        symbols(vIdx).DataType = dtMapped
        IF dtMapped = TYPE_UDT THEN
          symbols(vIdx).UDTIndex = typeData
        ELSE
          IF dtMapped = TYPE_STRING THEN
            fixedLen = typeData
            IF fixedLen > 0 THEN
              symbols(vIdx).FixedStrLen = fixedLen
              strVarData$(vIdx) = SPACE$(fixedLen)
            END IF
          END IF
        END IF
      END IF
    END IF

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
        tokIdx = tokIdx + 1
      ELSE
        throwCompilerError "EXPECTED COMMA", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF
  LOOP

  return2 endIdx
  parse_GLOBAL_Core = 1

END FUNCTION ' parse_GLOBAL_Core

''''''''''''''''''''''''
FUNCTION parse_GOSUB (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION

  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "GOSUB NEEDS LABEL", ASIS, 0
    EXIT FUNCTION
  END IF

  ff = verifyNoExtraTokens(endIdx, startIdx + 1, "GOSUB")
  IF ff = 0 THEN EXIT FUNCTION

  targetTok$ = lineTokens$(startIdx + 1)
  targetLabelName$ = "%" + UCASE$(targetTok$)

  expectedSymType = TYPE_LABEL
  ff = resolveSymbol(targetLabelName$)
  IF ff = 0 THEN
    EXIT FUNCTION
  END IF

  tira_Start

  retLbl$ = tiraLabelCreateNew$("GOSUB_RET")
  retAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tgtPtrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  baseAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)

  tiraOp TC_ADDRESS_OF, retAddrVar$, retLbl$, ""
  tiraOp TC_ADDRESS_OF, baseAddrVar$, "!G_SYS_GOSUB_ARR", ""

  tiraLeaSIB tgtPtrVar$, baseAddrVar$, "!G_SYS_GOSUB_IDX", "8"
  tiraWriteMem tgtPtrVar$, retAddrVar$, "8"
  tiraOp TC_ADD, "!G_SYS_GOSUB_IDX", "!G_SYS_GOSUB_IDX", "1"

  tiraScheduleHeapReset
  tiraJmpUser targetLabelName$

  tiraLabel retLbl$
  tiraScheduleHeapReset

  tira_EndAndProcess

  return2 endIdx
  parse_GOSUB = 1

END FUNCTION ' parse_GOSUB

''''''''''''''''''''''''
FUNCTION parse_GOTO (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION

  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "GOTO NEEDS LABEL", ASIS, 0
    EXIT FUNCTION
  END IF

  ff = verifyNoExtraTokens(endIdx, startIdx + 1, "GOTO")
  IF ff = 0 THEN EXIT FUNCTION

  targetTok$ = lineTokens$(startIdx + 1)
  targetLabelName$ = "%" + UCASE$(targetTok$)

  expectedSymType = TYPE_LABEL
  ff = resolveSymbol(targetLabelName$)
  IF ff = 0 THEN
    EXIT FUNCTION
  END IF
  vIdx = returnedData2

  tira_Start

  tiraScheduleHeapReset
  tiraJmpUser targetLabelName$

  tira_EndAndProcess

  return2 endIdx
  parse_GOTO = 1

END FUNCTION ' parse_GOTO

''''''''''''''''''''''''
FUNCTION parse_HEX$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM argDataType AS LONG
  DIM scratchName$
  DIM basePtr$
  DIM ptr$
  DIM loopTop$
  DIM digit$
  DIM charVar$
  DIM skipAlpha$
  DIM jmpWrite$
  DIM strLen$
  DIM endPtr$
  DIM descPtr$
  DIM workVar$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED HEX$", ASIS, 0
    parse_HEX$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED HEX$", ASIS, 0
    parse_HEX$ = ""
    EXIT FUNCTION
  END IF

  ' Sovereign command opens its own compilation block
  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  ' The Shunting Yard safely queues argument evaluation inside our pristine TIRA session
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_HEX$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "HEX$ REQUIRES NUMERIC ARGUMENT", ASIS, 0
    parse_HEX$ = ""
    EXIT FUNCTION
  END IF

  arg1$ = tiraForceInt$(arg1$)
  argDataType = exprIs.DataType

  scratchName$ = tiraResolveHoistVar$("HEX", "_DESC$")
  IF scratchName$ = "" THEN
    parse_HEX$ = ""
    EXIT FUNCTION
  END IF

  ' Copy the evaluated argument into a working variable to prevent mutating user variables
  workVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign workVar$, arg1$

  basePtr$ = tiraAllocTempMem$("16")

  ptr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, ptr$, basePtr$, "16"

  ' Mask the value to prevent infinite sign-extension loops for negative numbers

  SELECT CASE argDataType

    CASE TYPE_BYTE, TYPE_UBYTE
      tiraOp TC_AND, workVar$, workVar$, "255"
    CASE TYPE_INTEGER, TYPE_UINTEGER
      tiraOp TC_AND, workVar$, workVar$, "65535"
    CASE TYPE_LONG, TYPE_ULONG
      tiraOp TC_AND, workVar$, workVar$, "4294967295"

  END SELECT ' argDataType

  loopTop$ = tiraLabelCreateNew$("HEX_LOOP")
  tiraLabel loopTop$

  digit$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, digit$, workVar$, "15"

  charVar$ = tiraDimVar$("T", TYPE_LONG)
  skipAlpha$ = tiraLabelCreateNew$("HEX_SKIP_ALPHA")

  tiraJmpCond "JGE", digit$, "10", skipAlpha$

  ' 0-9
  tiraOp TC_ADD, charVar$, digit$, "48"
  jmpWrite$ = tiraLabelCreateNew$("HEX_WRITE")
  tiraJmp jmpWrite$

  tiraLabel skipAlpha$

  ' A-F
  tiraOp TC_ADD, charVar$, digit$, "55"

  tiraLabel jmpWrite$
  tiraOp TC_SUB, ptr$, ptr$, "1"
  tiraWriteMem ptr$, charVar$, "1"

  ' Shr performs a logical shift, injecting zeros into the upper bits.
  tiraOp TC_SHR, workVar$, workVar$, "4"

  tiraJmpCond "JNE", workVar$, "0", loopTop$

  strLen$ = tiraDimVar$("T", TYPE_LONG)
  endPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, endPtr$, basePtr$, "16"
  tiraOp TC_SUB, strLen$, endPtr$, ptr$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, ptr$, strLen$, "0"

  ' Close the block (NO HEAP RESET, so the string survives for the parent!)
  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_HEX$ = scratchName$

END FUNCTION ' parse_HEX$

''''''''''''''''''''''''
FUNCTION parse_IF (startIdx)

  DIM hasThen AS LONG
  DIM thenIdx AS LONG
  DIM ifID AS LONG
  DIM endIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  hasThen = 0
  thenIdx = 0

  ff = findNextTokenAtDepth0(startIdx + 1, endIdx, TOK_THEN)
  IF ff = 1 THEN
    hasThen = 1
    thenIdx = returnedData2
  END IF

  IF hasThen = 0 THEN
    throwCompilerError "MISSING THEN", ASIS, 0
    EXIT FUNCTION
  END IF

  ' Generate a globally unique ID for this IF block
  ifID = t.TiraVarCounter
  t.TiraVarCounter = t.TiraVarCounter + 1

  trueLbl$ = "@IF_TRUE_" + cTrNum$(ifID)
  falseLbl$ = "@IF_FALSE_" + cTrNum$(ifID)
  endLbl$ = "@IF_END_" + cTrNum$(ifID)

  tira_Start

  exprVar$ = tiraParseExpressionNumeric$(startIdx + 1, thenIdx - 1, ALIM, "TYPE MISMATCH IN CONDITION")
  IF exprVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  ' Anchor the True jump so execution flows into the THEN block
  tiraJmpCond "JNE", exprVar$, "0", trueLbl$
  tiraScheduleHeapReset
  tiraJmp falseLbl$

  tiraLabel trueLbl$
  tiraScheduleHeapReset

  tira_EndAndProcess

  ' Due to iterative Pass 2 flattening, single-line IF statements should never reach Pass 5.
  ' If there are tokens after THEN, something is structurally malformed in the source code.
  ff = verifyNoExtraTokens(endIdx, thenIdx, "THEN")
  IF ff = 0 THEN EXIT FUNCTION

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_IF
  ctrls(ctrlCount).Patch1 = ifID ' Save the IF block ID for ELSE and END IF
  ctrls(ctrlCount).Patch2 = 0 ' Unused in TIRA
  ctrlCount = ctrlCount + 1

  return2 thenIdx
  parse_IF = 1

END FUNCTION ' parse_IF

''''''''''''''''''''''''
FUNCTION parse_INKEY$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$
  DIM strLen$
  DIM dataPtr$
  DIM headPtr$
  DIM headVal$
  DIM tailPtr$
  DIM tailVal$
  DIM emptyLbl$
  DIM bufPtr$
  DIM charAddr$
  DIM charVal$
  DIM jmpDone$
  DIM keyIdx$
  DIM keyLoop$
  DIM keyState$
  DIM skipKey$
  DIM mappedKey$
  DIM nmpSkip$
  DIM ar1$
  DIM ar2$
  DIM ar3$
  DIM ar4$
  DIM descPtr$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED INKEY$", ASIS, 0
    parse_INKEY$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("INKEY", "_DESC$")
  IF scratchName$ = "" THEN
    parse_INKEY$ = ""
    EXIT FUNCTION
  END IF

  strLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign strLen$, "0"

  dataPtr$ = tiraAllocTempMem$("1")

  IF compileHasGraphics = 1 THEN
    headPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, headPtr$, "!G_LAYOUT_KBD_HEAD_VAL", ""
    headVal$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, headVal$ + ", " + headPtr$

    tailPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, tailPtr$, "!G_LAYOUT_KBD_TAIL_VAL", ""
    tailVal$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, tailVal$ + ", " + tailPtr$

    emptyLbl$ = tiraLabelCreateNew$("INKEY_EMPTY")
    tiraJmpCond "JE", headVal$, tailVal$, emptyLbl$

    bufPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADDRESS_OF, bufPtr$, "!G_LAYOUT_KBD_BUF_ARR", ""

    charAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, charAddr$, bufPtr$, tailVal$

    charVal$ = tiraDimVar$("T", TYPE_UBYTE)
    tiraNew TC_READ_MEM, charVal$ + ", " + charAddr$

    tiraOp TC_ADD, tailVal$, tailVal$, "1"
    tiraOp TC_AND, tailVal$, tailVal$, "255"
    tiraWriteMem tailPtr$, tailVal$, "4"

    tiraWriteMem dataPtr$, charVal$, "1"
    tiraAssign strLen$, "1"

    jmpDone$ = tiraLabelCreateNew$("INKEY_DONE")
    tiraJmp jmpDone$

    tiraLabel emptyLbl$
    tiraAssign dataPtr$, "0"
    tiraLabel jmpDone$
  ELSE
    keyIdx$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign keyIdx$, "8"

    keyLoop$ = tiraLabelCreateNew$("INKEY_KLOOP")
    tiraLabel keyLoop$

    tiraCall "IAT_GETASYNCKEYSTATE", 1, keyIdx$
    keyState$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_GET_RET, keyState$

    tiraOp TC_AND, keyState$, keyState$, "32768"
    skipKey$ = tiraLabelCreateNew$("INKEY_SKIP")
    tiraJmpCond "JE", keyState$, "0", skipKey$

    mappedKey$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign mappedKey$, keyIdx$

    nmpSkip$ = tiraLabelCreateNew$("INKEY_NMPSKIP")
    tiraJmpCond "JL", mappedKey$, "96", nmpSkip$
    tiraJmpCond "JG", mappedKey$, "105", nmpSkip$
    tiraOp TC_SUB, mappedKey$, mappedKey$, "48"
    tiraLabel nmpSkip$

    ar1$ = tiraLabelCreateNew$("INKEY_AR1")
    tiraJmpCond "JNE", mappedKey$, "37", ar1$
    tiraAssign mappedKey$, "52"
    tiraLabel ar1$

    ar2$ = tiraLabelCreateNew$("INKEY_AR2")
    tiraJmpCond "JNE", mappedKey$, "38", ar2$
    tiraAssign mappedKey$, "56"
    tiraLabel ar2$

    ar3$ = tiraLabelCreateNew$("INKEY_AR3")
    tiraJmpCond "JNE", mappedKey$, "39", ar3$
    tiraAssign mappedKey$, "54"
    tiraLabel ar3$

    ar4$ = tiraLabelCreateNew$("INKEY_AR4")
    tiraJmpCond "JNE", mappedKey$, "40", ar4$
    tiraAssign mappedKey$, "50"
    tiraLabel ar4$

    tiraWriteMem dataPtr$, mappedKey$, "1"
    tiraAssign strLen$, "1"
    jmpDone$ = tiraLabelCreateNew$("INKEY_DONE")
    tiraJmp jmpDone$

    tiraLabel skipKey$
    tiraOp TC_ADD, keyIdx$, keyIdx$, "1"
    tiraJmpCond "JLE", keyIdx$, "255", keyLoop$

    tiraAssign dataPtr$, "0"
    tiraLabel jmpDone$
  END IF

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tiraInjectPendingDisplayFlush

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_INKEY$ = scratchName$

END FUNCTION ' parse_INKEY$

''''''''''''''''''''''''
FUNCTION parse_INKEYF$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$
  DIM dataPtr$
  DIM loopTop$
  DIM keyIdx$
  DIM keyLoop$
  DIM keyState$
  DIM skipKey$
  DIM mappedKey$
  DIM nmpSkip$
  DIM ar1$
  DIM ar2$
  DIM ar3$
  DIM ar4$
  DIM jmpDone$
  DIM descPtr$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED INKEYF$", ASIS, 0
    parse_INKEYF$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("INKEYF", "_DESC$")
  IF scratchName$ = "" THEN
    parse_INKEYF$ = ""
    EXIT FUNCTION
  END IF

  dataPtr$ = tiraAllocTempMem$("1")

  loopTop$ = tiraLabelCreateNew$("INKEYF_TOP")
  tiraLabel loopTop$

  tiraCall "IAT_SLEEP", 1, "10"

  keyIdx$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign keyIdx$, "8"

  keyLoop$ = tiraLabelCreateNew$("INKEYF_KLOOP")
  tiraLabel keyLoop$

  tiraCall "IAT_GETASYNCKEYSTATE", 1, keyIdx$
  keyState$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, keyState$

  tiraOp TC_AND, keyState$, keyState$, "32768"
  skipKey$ = tiraLabelCreateNew$("INKEYF_SKIP")
  tiraJmpCond "JE", keyState$, "0", skipKey$

  mappedKey$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign mappedKey$, keyIdx$

  nmpSkip$ = tiraLabelCreateNew$("INKEYF_NMPSKIP")
  tiraJmpCond "JL", mappedKey$, "96", nmpSkip$
  tiraJmpCond "JG", mappedKey$, "105", nmpSkip$
  tiraOp TC_SUB, mappedKey$, mappedKey$, "48"
  tiraLabel nmpSkip$

  ar1$ = tiraLabelCreateNew$("INKEYF_AR1")
  tiraJmpCond "JNE", mappedKey$, "37", ar1$
  tiraAssign mappedKey$, "52"
  tiraLabel ar1$

  ar2$ = tiraLabelCreateNew$("INKEYF_AR2")
  tiraJmpCond "JNE", mappedKey$, "38", ar2$
  tiraAssign mappedKey$, "56"
  tiraLabel ar2$

  ar3$ = tiraLabelCreateNew$("INKEYF_AR3")
  tiraJmpCond "JNE", mappedKey$, "39", ar3$
  tiraAssign mappedKey$, "54"
  tiraLabel ar3$

  ar4$ = tiraLabelCreateNew$("INKEYF_AR4")
  tiraJmpCond "JNE", mappedKey$, "40", ar4$
  tiraAssign mappedKey$, "50"
  tiraLabel ar4$

  tiraWriteMem dataPtr$, mappedKey$, "1"
  jmpDone$ = tiraLabelCreateNew$("INKEYF_DONE")
  tiraJmp jmpDone$

  tiraLabel skipKey$
  tiraOp TC_ADD, keyIdx$, keyIdx$, "1"
  tiraJmpCond "JLE", keyIdx$, "255", keyLoop$
  tiraJmp loopTop$

  tiraLabel jmpDone$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, "1", "0"

  tiraInjectPendingDisplayFlush

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_INKEYF$ = scratchName$

END FUNCTION ' parse_INKEYF$

''''''''''''''''''''''''
FUNCTION parse_INPUT (startIdx)

  tokIdx = startIdx + 1

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF tokIdx > endIdx THEN
    throwCompilerError "EXPECTED VARIABLE", ASIS, 0
    EXIT FUNCTION
  END IF

  hasPrompt = 0
  promptStr$ = ""
  IF LEFT$(lineTokens$(tokIdx), 1) = CHR$(34) THEN
    hasPrompt = 1
    promptStr$ = extractQuotes$(lineTokens$(tokIdx))
    tokIdx = tokIdx + 1
    IF tokIdx > endIdx THEN
      throwCompilerError "EXPECTED VARIABLE", ASIS, 0
      EXIT FUNCTION
    END IF
    tVal = lineTokenVals(tokIdx)
    IF tVal = 256 + ASC(";") OR tVal = 256 + ASC(",") THEN
      tokIdx = tokIdx + 1
    ELSE
      throwCompilerError "EXPECTED ; OR ,", ASIS, 0
      EXIT FUNCTION
    END IF
  END IF

  IF tokIdx > endIdx THEN
    throwCompilerError "EXPECTED VARIABLE", ASIS, 0
    EXIT FUNCTION
  END IF

  vTok$ = lineTokens$(tokIdx)
  IF lineTokenVals(tokIdx) <> 0 THEN
    throwCompilerError "EXPECTED VARIABLE", ASIS, 0
    EXIT FUNCTION
  END IF

  vName$ = UCASE$(vTok$)

  ff = resolveSymbol(vName$)
  IF ff = 0 THEN
    EXIT FUNCTION
  END IF
  vIdx = returnedData2

  isStrVar = 0
  IF returnedData3 = TYPE_STRING THEN
    isStrVar = 1
  END IF

  IF hasPrompt = 1 THEN
    pStr$ = promptStr$
  ELSE
    pStr$ = "? "
  END IF

  ff = resolveSymbol("!G_EVAL_LIT__" + cTrNum$(t.TiraVarCounter) + "_DESC$")
  t.TiraVarCounter = t.TiraVarCounter + 1
  IF ff = 0 THEN EXIT FUNCTION
  litIdx = returnedData2
  strVarData$(litIdx) = pStr$

  tira_Start

  litName$ = "!G_EVAL_LIT__" + cTrNum$(t.TiraVarCounter - 1) + "_DESC$"
  litPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign litPtr$, litName$

  IF compileHasGraphics = 0 THEN
    tiraCall "RT_PRINT_STR", 1, litPtr$
  END IF

  tgtAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, tgtAddr$, RTRIM$(symbols(vIdx).RecordName), ""

  tiraCall "RT_INPUT", 4, tgtAddr$ + ", " + cTrNum$(isStrVar) + ", " + litPtr$ + ", " + cTrNum$(symbols(vIdx).DataType)

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_INPUT = 1

END FUNCTION ' parse_INPUT

''''''''''''''''''''''''
FUNCTION parse_INT$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM floatArg$
  DIM floatTrunc$
  DIM skipDecLbl$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED INT", ASIS, 0
    parse_INT$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED INT", ASIS, 0
    parse_INT$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_INT$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_INT$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("INT", "_VAL")
  IF scratchName$ = "" THEN
    parse_INT$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, arg1$ ' Truncates float to int naturally

  floatArg$ = tiraDimVar$("T", TYPE_DOUBLE)
  tiraAssign floatArg$, arg1$

  floatTrunc$ = tiraDimVar$("T", TYPE_DOUBLE)
  tiraAssign floatTrunc$, resVar$

  skipDecLbl$ = tiraLabelCreateNew$("SKIP_DEC")
  tiraJmpCond "JGE", floatArg$, floatTrunc$, skipDecLbl$
  tiraOp TC_SUB, resVar$, resVar$, "1"
  tiraLabel skipDecLbl$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_INT$ = scratchName$

END FUNCTION ' parse_INT$

''''''''''''''''''''''''
FUNCTION parse_KEYDOWN$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED _KEYDOWN", ASIS, 0
    parse_KEYDOWN$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED _KEYDOWN", ASIS, 0
    parse_KEYDOWN$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_KEYDOWN$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_KEYDOWN$ = ""
    EXIT FUNCTION
  END IF

  arg1$ = tiraForceInt$(arg1$)

  scratchName$ = tiraResolveHoistVar$("KEYDOWN", "_VAL")
  IF scratchName$ = "" THEN
    parse_KEYDOWN$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraCall "RT_KEYDOWN", 1, arg1$
  tiraNew TC_GET_RET, resVar$

  tiraInjectPendingDisplayFlush

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_KEYDOWN$ = scratchName$

END FUNCTION ' parse_KEYDOWN$

''''''''''''''''''''''''
FUNCTION parse_KILL (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "EXPECTED FILENAME AFTER KILL", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  fileNameVar$ = tiraParseExpression$(startIdx + 1, endIdx, ALIM)
  IF fileNameVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "FILENAME MUST BE STRING", ASIS, 0
    EXIT FUNCTION
  END IF

  strDataPtr$ = tiraGetStringData$(fileNameVar$)

  tiraCall "IAT_DELETEFILEA", 1, strDataPtr$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_KILL = 1

END FUNCTION ' parse_KILL

''''''''''''''''''''''''
FUNCTION parse_LEFT$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM arg2$
  DIM scratchName$
  DIM srcPtr$
  DIM strLen$
  DIM dataPtr$
  DIM descPtr$
  DIM comma1 AS LONG

  IF startIdx + 5 > endIdx THEN
    throwCompilerError "MALFORMED LEFT$", ASIS, 0
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED LEFT$", ASIS, 0
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 2, endIdx - 1)

  IF comma1 = 0 THEN
    throwCompilerError "LEFT$ REQUIRES TWO ARGUMENTS", ASIS, 0
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, comma1 - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF
  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "LEFT$ ARG 1 MUST BE STRING", ASIS, 0
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  arg2$ = tiraParseExpressionInt$(comma1 + 1, endIdx - 1, allowImplicit, "LEFT$ ARG 2 MUST BE NUMERIC")
  IF arg2$ = "" THEN
    tira_Cancel
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("LEFT", "_DESC$")
  IF scratchName$ = "" THEN
    parse_LEFT$ = ""
    EXIT FUNCTION
  END IF

  srcPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  tiraClamp arg2$, "0", strLen$

  tiraAssign strLen$, arg2$

  dataPtr$ = tiraAllocTempMem$(strLen$)

  tiraMemcpy dataPtr$, srcPtr$, strLen$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_LEFT$ = scratchName$

END FUNCTION ' parse_LEFT$

''''''''''''''''''''''''
FUNCTION parse_LEN$ (startIdx, endIdx, allowImplicit)

  DIM isVariableLen AS LONG
  DIM reqSize AS LONG
  DIM fixedLen AS LONG
  DIM innerStart AS LONG
  DIM innerEnd AS LONG
  DIM firstChar AS STRING * 1
  DIM vIdx AS LONG
  DIM isMatch AS LONG
  DIM isArrayWhole AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM isValidSize AS LONG
  DIM scratchName$
  DIM resVar$
  DIM arg1$
  DIM firstTok$
  DIM vName$
  DIM lenVar$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED LEN", ASIS, 0
    parse_LEN$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED LEN", ASIS, 0
    parse_LEN$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  innerStart = startIdx + 2
  innerEnd = endIdx - 1
  isVariableLen = 0
  reqSize = 0

  firstTok$ = lineTokens$(innerStart)
  IF lineTokenVals(innerStart) = 0 THEN
    firstChar = LEFT$(firstTok$, 1)
    IF (firstChar >= "A" AND firstChar <= "Z") OR (firstChar >= "a" AND firstChar <= "z") OR firstChar = "_" THEN
      vName$ = UCASE$(firstTok$)
      IF findSymbol(vName$) THEN
        vIdx = returnedData2
        isMatch = 0
        isArrayWhole = 0

        IF innerStart = innerEnd THEN
          isMatch = 1
        ELSE
          IF innerStart + 2 = innerEnd THEN
            IF lineTokenVals(innerStart + 1) = 256 + ASC("(") AND lineTokenVals(innerEnd) = 256 + ASC(")") THEN
              isMatch = 1
              isArrayWhole = 1
            END IF
          ELSE
            IF lineTokenVals(innerStart + 1) = 256 + ASC("(") THEN
              IF findMatchingParen(innerStart + 1, innerEnd) = 1 THEN
                IF returnedData2 = innerEnd THEN
                  isMatch = 1
                END IF
              END IF
            END IF
          END IF
        END IF

        IF isMatch = 1 THEN
          dt = symbols(vIdx).DataType
          elemSize = 0
          isValidSize = 1

          SELECT CASE dt

            CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
            CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
            CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
            CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
            CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
            CASE TYPE_STRING:
              fixedLen = retFixedStringLength(vIdx)
              IF fixedLen > 0 THEN
                elemSize = fixedLen
              ELSE
                isValidSize = 0
                elemSize = 0
              END IF

          END SELECT ' dt

          IF isArrayWhole = 1 THEN
            IF symbols(vIdx).IsArray = 0 THEN
              throwCompilerErrorAndCancelTira "EXPECTED ARRAY", ASIS, 0
              parse_LEN$ = ""
              EXIT FUNCTION
            END IF
            IF isValidSize = 0 THEN
              throwCompilerErrorAndCancelTira "CANNOT USE LEN ON DYNAMIC STRING ARRAY", ASIS, 0
              parse_LEN$ = ""
              EXIT FUNCTION
            END IF
            reqSize = elemSize * symbols(vIdx).Size
            isVariableLen = 1
          ELSE
            IF dt <> TYPE_STRING THEN
              reqSize = elemSize
              isVariableLen = 1
            END IF
          END IF
        END IF
      END IF
    END IF
  END IF

  scratchName$ = tiraResolveHoistVar$("LEN", "_VAL")
  IF scratchName$ = "" THEN
    parse_LEN$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)

  IF isVariableLen = 1 THEN
    tiraAssign resVar$, LTRIM$(STR$(reqSize))
  ELSE
    IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
    arg1$ = tiraParseExpression$(innerStart, innerEnd, allowImplicit)
    IF arg1$ = "" THEN
      tira_Cancel
      parse_LEN$ = ""
      EXIT FUNCTION
    END IF
    IF exprIs.DataType <> TYPE_STRING THEN
      throwCompilerErrorAndCancelTira "LEN REQUIRES STRING ARGUMENT", ASIS, 0
      parse_LEN$ = ""
      EXIT FUNCTION
    END IF

    lenVar$ = tiraGetStringLen$(arg1$)
    tiraAssign resVar$, lenVar$
  END IF

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_LEN$ = scratchName$

END FUNCTION ' parse_LEN$

''''''''''''''''''''''''
FUNCTION parse_LINE (startIdx)

  DIM boxType AS LONG

  tokIdx = startIdx + 1

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF tokIdx > endIdx THEN
    throwCompilerError "EXPECTED ( AFTER LINE", ASIS, 0
    EXIT FUNCTION
  END IF

  IF lineTokenVals(tokIdx) <> 256 + ASC("(") THEN
    throwCompilerError "EXPECTED ( AFTER LINE", ASIS, 0
    EXIT FUNCTION
  END IF

  hasDash = 0
  dashIdx = 0

  ff = findNextTokenAtDepth0(tokIdx, endIdx, 256 + ASC("-"))
  IF ff = 1 THEN
    hasDash = 1
    dashIdx = returnedData2
  END IF

  IF hasDash = 0 THEN
    throwCompilerError "LINE MISSING -", ASIS, 0
    EXIT FUNCTION
  END IF

  IF dashIdx + 1 > endIdx THEN
    throwCompilerError "EXPECTED ( AFTER -", ASIS, 0
    EXIT FUNCTION
  END IF

  IF lineTokenVals(dashIdx + 1) <> 256 + ASC("(") THEN
    throwCompilerError "EXPECTED ( AFTER -", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  '''' Parse X1, Y1
  cComma = retCoordinateBoundaries(tokIdx, dashIdx - 1)
  IF cComma = 0 THEN
    throwCompilerError "LINE MISSING X1, Y1", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF
  cStart = returnedData2
  cEnd = returnedData3

  x1$ = tiraParseExpressionInt$(cStart, cComma - 1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF x1$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  y1$ = tiraParseExpressionInt$(cComma + 1, cEnd, ALIM, "COORDINATE MUST BE NUMERIC")
  IF y1$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  '''' Parse X2, Y2, Color, Box
  comma3 = findComma(dashIdx + 1, endIdx)
  comma4 = 0
  IF comma3 > 0 THEN
    comma4 = findComma(comma3 + 1, endIdx)
  END IF

  p2End = endIdx
  IF comma3 > 0 THEN p2End = comma3 - 1

  cComma = retCoordinateBoundaries(dashIdx + 1, p2End)
  IF cComma = 0 THEN
    throwCompilerError "LINE MISSING X2, Y2", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF
  cStart = returnedData2
  cEnd = returnedData3

  x2$ = tiraParseExpressionInt$(cStart, cComma - 1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF x2$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  y2$ = tiraParseExpressionInt$(cComma + 1, cEnd, ALIM, "COORDINATE MUST BE NUMERIC")
  IF y2$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  '''' Parse color
  IF comma3 > 0 THEN
    colEnd = endIdx
    IF comma4 > 0 THEN colEnd = comma4 - 1
    IF comma3 + 1 > colEnd THEN
      colorVar$ = "!G_GFX_FG_VAL"
    ELSE
      colorVar$ = tiraParseExpressionInt$(comma3 + 1, colEnd, ALIM, "COLOR MUST BE NUMERIC")
      IF colorVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF
  ELSE
    colorVar$ = "!G_GFX_FG_VAL"
  END IF

  '''' Parse box flag
  boxType = 0
  IF comma4 > 0 THEN
    boxStr$ = UCASE$(lineTokens$(comma4 + 1))
    IF boxStr$ = "B" THEN boxType = 1
    IF boxStr$ = "BF" THEN boxType = 2
  END IF

  ' Compile arguments and invoke the runtime routine natively via TIRA
  tiraCall "RT_LINE", 7, x1$ + ", " + y1$ + ", " + x2$ + ", " + y2$ + ", " + colorVar$ + ", " + LTRIM$(RTRIM$(STR$(boxType))) + ", 65535"

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_LINE = 1

END FUNCTION ' parse_LINE

''''''''''''''''''''''''
FUNCTION parse_LOCATE (startIdx)

  DIM endIdx AS LONG
  DIM commaIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  commaIdx = findComma(startIdx + 1, endIdx)

  tira_Start

  IF commaIdx = 0 THEN
    yStr$ = tiraParseExpressionInt$(startIdx + 1, endIdx, ALIM, "LOCATE REQUIRES NUMERIC")
    IF yStr$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    xStr$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign xStr$, "1"
  ELSE
    yStr$ = tiraParseExpressionInt$(startIdx + 1, commaIdx - 1, ALIM, "LOCATE REQUIRES NUMERIC")
    IF yStr$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    xStr$ = tiraParseExpressionInt$(commaIdx + 1, endIdx, ALIM, "LOCATE REQUIRES NUMERIC")
    IF xStr$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
  END IF

  tiraOp TC_SUB, yStr$, yStr$, "1"
  tiraOp TC_SUB, xStr$, xStr$, "1"

  IF compileHasGraphics = 1 THEN
    tiraOp TC_SHL, "!G_GFX_CUR_Y_VAL", yStr$, "3"
    tiraOp TC_SHL, "!G_GFX_CUR_X_VAL", xStr$, "3"
  ELSE
    packedY$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_SHL, packedY$, yStr$, "16"

    cleanX$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_AND, cleanX$, xStr$, "65535"

    coord$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_OR, coord$, packedY$, cleanX$

    hndVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraCall "IAT_GETSTDHANDLE", 1, "-11"
    tiraNew TC_GET_RET, hndVar$

    tiraCall "IAT_SETCONSOLECURSORPOSITION", 2, hndVar$ + ", " + coord$
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_LOCATE = 1

END FUNCTION ' parse_LOCATE

''''''''''''''''''''''''
FUNCTION parse_LOF$ (startIdx, endIdx, allowImplicit)

  DIM fileNumStart AS LONG
  DIM fileNumVar$
  DIM scratchName$
  DIM baseArr$
  DIM slotAddr$
  DIM handleVar$
  DIM resVar$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED LOF", ASIS, 0
    parse_LOF$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED LOF", ASIS, 0
    parse_LOF$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  fileNumStart = startIdx + 2

  ' Strip the # symbol so the expression evaluates properly
  IF lineTokens$(fileNumStart) = "#" THEN
    fileNumStart = fileNumStart + 1
  ELSE
    IF LEFT$(lineTokens$(fileNumStart), 1) = "#" THEN
      lineTokens$(fileNumStart) = MID$(lineTokens$(fileNumStart), 2)
    END IF
  END IF

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  fileNumVar$ = tiraParseExpressionInt$(fileNumStart, endIdx - 1, allowImplicit, "FILENUM MUST BE NUMERIC")
  IF fileNumVar$ = "" THEN
    tira_Cancel
    parse_LOF$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("LOF", "_VAL")
  IF scratchName$ = "" THEN
    parse_LOF$ = ""
    EXIT FUNCTION
  END IF

  baseArr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, baseArr$, "!G_LAYOUT_FILE_HANDLES_ARR", ""

  slotAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraLeaSIB slotAddr$, baseArr$, fileNumVar$, "8"

  handleVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, handleVar$ + ", " + slotAddr$

  tiraCall "IAT_GETFILESIZE", 2, handleVar$ + ", 0"
  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, resVar$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_LOF$ = scratchName$

END FUNCTION ' parse_LOF$

''''''''''''''''''''''''
FUNCTION parse_LOOP (startIdx)

  DIM endIdx AS LONG
  DIM loopID AS LONG
  DIM hasCond AS LONG
  DIM tVal AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "LOOP WITHOUT DO", ASIS, 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_DO THEN
    throwCompilerError "LOOP MISMATCH", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrlCount = ctrlCount - 1
  loopID = ctrls(ctrlCount).Patch1

  topLbl$ = "@DO_TOP_" + cTrNum$(loopID)
  doneLbl$ = "@DO_DONE_" + cTrNum$(loopID)

  hasCond = 0

  IF endIdx > startIdx THEN
    tVal = lineTokenVals(startIdx + 1)
    IF tVal = TOK_UNTIL OR tVal = TOK_WHILE THEN
      hasCond = 1
    ELSE
      throwCompilerError "EXPECTED UNTIL OR WHILE", ASIS, 0
      EXIT FUNCTION
    END IF
  END IF

  resetLbl$ = "@DO_RESET_" + cTrNum$(loopID)

  tira_Start

  IF hasCond = 1 THEN
    exprVar$ = tiraParseExpressionNumeric$(startIdx + 2, endIdx, ALIM, "TYPE MISMATCH IN CONDITION")
    IF exprVar$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    IF tVal = TOK_UNTIL THEN
      tiraJmpCond "JNE", exprVar$, "0", doneLbl$
    ELSE
      tiraJmpCond "JE", exprVar$, "0", doneLbl$
    END IF

    tiraScheduleHeapReset
    tiraJmp topLbl$
  ELSE
    tiraScheduleHeapReset
    tiraJmp topLbl$
  END IF

  ' Anchor the end of the loop in the TIRA symbol table
  tiraLabel doneLbl$
  tiraScheduleHeapReset

  tira_EndAndProcess

  return2 endIdx
  parse_LOOP = 1

END FUNCTION ' parse_LOOP

''''''''''''''''''''''''
FUNCTION parse_LTRIM$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM origPtr$
  DIM origLen$
  DIM dataPtr$
  DIM strLen$
  DIM loopTop$
  DIM loopDone$
  DIM byteVal$
  DIM isSpaceLbl$
  DIM descPtr$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED LTRIM$", ASIS, 0
    parse_LTRIM$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED LTRIM$", ASIS, 0
    parse_LTRIM$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_LTRIM$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "LTRIM$ REQUIRES STRING ARGUMENT", ASIS, 0
    parse_LTRIM$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("LTRIM", "_DESC$")
  IF scratchName$ = "" THEN
    parse_LTRIM$ = ""
    EXIT FUNCTION
  END IF

  origPtr$ = tiraGetStringData$(arg1$)
  origLen$ = tiraGetStringLen$(arg1$)

  dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign dataPtr$, origPtr$
  strLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign strLen$, origLen$

  loopTop$ = tiraLabelCreateNew$("LTRIM_LOOP")
  loopDone$ = tiraLabelCreateNew$("LTRIM_DONE")

  tiraLabel loopTop$
  tiraJmpCond "JLE", strLen$, "0", loopDone$

  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, byteVal$ + ", " + dataPtr$

  isSpaceLbl$ = tiraLabelCreateNew$("LTRIM_IS_SPC")
  tiraJmpCond "JE", byteVal$, "32", isSpaceLbl$
  tiraJmpCond "JNE", byteVal$, "9", loopDone$
  tiraLabel isSpaceLbl$

  tiraOp TC_ADD, dataPtr$, dataPtr$, "1"
  tiraOp TC_SUB, strLen$, strLen$, "1"
  tiraJmp loopTop$

  tiraLabel loopDone$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_LTRIM$ = scratchName$

END FUNCTION ' parse_LTRIM$

''''''''''''''''''''''''
FUNCTION parse_MID$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM arg2$
  DIM arg3$
  DIM comma1 AS LONG
  DIM comma2 AS LONG
  DIM scratchName$
  DIM resVar$
  DIM srcPtr$
  DIM strLen$
  DIM startIdxVar$
  DIM remLen$
  DIM dataPtr$
  DIM descPtr$

  IF startIdx + 5 > endIdx THEN
    throwCompilerError "MALFORMED MID$", ASIS, 0
    parse_MID$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED MID$", ASIS, 0
    parse_MID$ = ""
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 2, endIdx - 1)

  IF comma1 = 0 THEN
    throwCompilerError "MALFORMED MID$", ASIS, 0
    parse_MID$ = ""
    EXIT FUNCTION
  END IF

  comma2 = findComma(comma1 + 1, endIdx - 1)

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, comma1 - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_MID$ = ""
    EXIT FUNCTION
  END IF
  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "MID$ ARG 1 MUST BE STRING", ASIS, 0
    parse_MID$ = ""
    EXIT FUNCTION
  END IF

  IF comma2 > 0 THEN
    IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
    arg2$ = tiraParseExpressionInt$(comma1 + 1, comma2 - 1, allowImplicit, "MID$ ARG 2 MUST BE NUMERIC")
    IF arg2$ = "" THEN
      tira_Cancel
      parse_MID$ = ""
      EXIT FUNCTION
    END IF

    IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
    arg3$ = tiraParseExpressionInt$(comma2 + 1, endIdx - 1, allowImplicit, "MID$ ARG 3 MUST BE NUMERIC")
    IF arg3$ = "" THEN
      tira_Cancel
      parse_MID$ = ""
      EXIT FUNCTION
    END IF
  ELSE
    IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
    arg2$ = tiraParseExpressionInt$(comma1 + 1, endIdx - 1, allowImplicit, "MID$ ARG 2 MUST BE NUMERIC")
    IF arg2$ = "" THEN
      tira_Cancel
      parse_MID$ = ""
      EXIT FUNCTION
    END IF
    arg3$ = "&H7FFFFFFF" ' Max integer length to act as missing arg
  END IF

  scratchName$ = tiraResolveHoistVar$("MID", "_DESC$")
  IF scratchName$ = "" THEN
    parse_MID$ = ""
    EXIT FUNCTION
  END IF

  srcPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  startIdxVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, startIdxVar$, arg2$, "1"

  tiraClamp startIdxVar$, "0", strLen$

  remLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, remLen$, strLen$, startIdxVar$

  tiraClamp remLen$, "0", arg3$

  tiraOp TC_ADD, srcPtr$, srcPtr$, startIdxVar$
  tiraAssign strLen$, remLen$

  dataPtr$ = tiraAllocTempMem$(strLen$)

  tiraMemcpy dataPtr$, srcPtr$, strLen$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_MID$ = scratchName$

END FUNCTION ' parse_MID$

''''''''''''''''''''''''
FUNCTION parse_MOUSEBUTTON$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM lblB2$
  DIM lblB3$
  DIM lblEnd$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED _MOUSEBUTTON", ASIS, 0
    parse_MOUSEBUTTON$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED _MOUSEBUTTON", ASIS, 0
    parse_MOUSEBUTTON$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_MOUSEBUTTON$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_MOUSEBUTTON$ = ""
    EXIT FUNCTION
  END IF

  arg1$ = tiraForceInt$(arg1$)

  scratchName$ = tiraResolveHoistVar$("MOUSEBUTTON", "_VAL")
  IF scratchName$ = "" THEN
    parse_MOUSEBUTTON$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)

  lblB2$ = tiraLabelCreateNew$("MB_2")
  lblB3$ = tiraLabelCreateNew$("MB_3")
  lblEnd$ = tiraLabelCreateNew$("MB_END")

  tiraJmpCond "JE", arg1$, "2", lblB2$
  tiraJmpCond "JE", arg1$, "3", lblB3$
  tiraAssign resVar$, "!G_IO_MOUSE_B1_VAL"
  tiraJmp lblEnd$

  tiraLabel lblB2$
  tiraAssign resVar$, "!G_IO_MOUSE_B2_VAL"
  tiraJmp lblEnd$

  tiraLabel lblB3$
  tiraAssign resVar$, "!G_IO_MOUSE_B3_VAL"

  tiraLabel lblEnd$
  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_MOUSEBUTTON$ = scratchName$

END FUNCTION ' parse_MOUSEBUTTON$

''''''''''''''''''''''''
FUNCTION parse_MOUSEINPUT$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$
  DIM resVar$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED _MOUSEINPUT", ASIS, 0
    parse_MOUSEINPUT$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("MOUSEINPUT", "_VAL")
  IF scratchName$ = "" THEN
    parse_MOUSEINPUT$ = ""
    EXIT FUNCTION
  END IF

  tiraCall "RT_MOUSEINPUT", 0, ""

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, resVar$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_MOUSEINPUT$ = scratchName$

END FUNCTION ' parse_MOUSEINPUT$

''''''''''''''''''''''''
FUNCTION parse_MOUSEX$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED _MOUSEX", ASIS, 0
    parse_MOUSEX$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("MOUSEX", "_VAL")
  IF scratchName$ = "" THEN
    parse_MOUSEX$ = ""
    EXIT FUNCTION
  END IF

  tiraAssign scratchName$, "!G_IO_MOUSE_X_VAL"

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_MOUSEX$ = scratchName$

END FUNCTION ' parse_MOUSEX$

''''''''''''''''''''''''
FUNCTION parse_MOUSEY$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED _MOUSEY", ASIS, 0
    parse_MOUSEY$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("MOUSEY", "_VAL")
  IF scratchName$ = "" THEN
    parse_MOUSEY$ = ""
    EXIT FUNCTION
  END IF

  tiraAssign scratchName$, "!G_IO_MOUSE_Y_VAL"

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_MOUSEY$ = scratchName$

END FUNCTION ' parse_MOUSEY$

''''''''''''''''''''''''
FUNCTION parse_MOUSEWHEEL$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED _MOUSEWHEEL", ASIS, 0
    parse_MOUSEWHEEL$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("MOUSEWHEEL", "_VAL")
  IF scratchName$ = "" THEN
    parse_MOUSEWHEEL$ = ""
    EXIT FUNCTION
  END IF

  tiraAssign scratchName$, "!G_IO_MOUSE_SCRL_VAL"

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_MOUSEWHEEL$ = scratchName$

END FUNCTION ' parse_MOUSEWHEEL$

''''''''''''''''''''''''
FUNCTION parse_NEXT (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "NEXT WITHOUT FOR", ASIS, 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_FOR THEN
    throwCompilerError "NEXT MISMATCH", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrlCount = ctrlCount - 1
  vIdx = ctrls(ctrlCount).ForVarIdx
  loopID = ctrls(ctrlCount).Patch1

  IF endIdx > startIdx THEN
    vTok$ = lineTokens$(startIdx + 1)
    baseName$ = UCASE$(vTok$)
    IF baseName$ <> RTRIM$(symbols(vIdx).RecordName) THEN
      throwCompilerError "NEXT VAR MISMATCH", ASIS, 0
      EXIT FUNCTION
    END IF
  END IF

  tira_Start

  vNameTira$ = RTRIM$(symbols(vIdx).RecordName)
  endNameTira$ = "!G_SYS_FOR_END_" + cTrNum$(loopID) + "_VAL"
  stepNameTira$ = "!G_SYS_FOR_STEP_" + cTrNum$(loopID) + "_VAL"

  lblTop$ = "@FOR_TOP_" + cTrNum$(loopID)
  lblCond$ = "@FOR_COND_" + cTrNum$(loopID)
  lblPosStep$ = "@FOR_POS_" + cTrNum$(loopID)
  lblNegStep$ = "@FOR_NEG_" + cTrNum$(loopID)
  lblEndNext$ = "@FOR_DONE_" + cTrNum$(loopID)

  ' Apply step logic
  tiraOp TC_ADD, vNameTira$, vNameTira$, stepNameTira$
  tiraLabel lblCond$

  ' Test step direction
  tiraJmpCond "JL", stepNameTira$, "0", lblNegStep$

  ' Positive Step Check (Jump to end if we exceeded the boundary)
  tiraLabel lblPosStep$
  tiraJmpCond "JG", vNameTira$, endNameTira$, lblEndNext$
  tiraScheduleHeapReset
  tiraJmp lblTop$

  ' Negative Step Check (Jump to end if we exceeded the boundary)
  tiraLabel lblNegStep$
  tiraJmpCond "JL", vNameTira$, endNameTira$, lblEndNext$
  tiraScheduleHeapReset
  tiraJmp lblTop$

  ' Loop conclusion
  tiraLabel lblEndNext$
  tiraScheduleHeapReset

  tira_EndAndProcess

  return2 endIdx
  parse_NEXT = 1

END FUNCTION ' parse_NEXT

''''''''''''''''''''''''
FUNCTION parse_PEEK$ (startIdx, endIdx, allowImplicit)

  ' This function evaluates the peek command to read data from memory
  ' We specifically check if the script is trying to read address 1047 which is the
  ' legacy dos keyboard flags byte. If 1047 is requested, we ask windows for the
  ' current numlock state, extract the active bit, and shift it left by five positions
  ' so it perfectly matches the legacy bitmask expected by older games

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM skipLbl$
  DIM stateVar$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED PEEK", ASIS, 0
    parse_PEEK$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED PEEK", ASIS, 0
    parse_PEEK$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  ' Evaluate the memory address argument passed to the peek function
  arg1$ = tiraParseExpressionInt$(startIdx + 2, endIdx - 1, allowImplicit, "PEEK REQUIRES NUMERIC ARGUMENT")
  IF arg1$ = "" THEN
    tira_Cancel
    parse_PEEK$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("PEEK", "_VAL")
  IF scratchName$ = "" THEN
    parse_PEEK$ = ""
    EXIT FUNCTION
  END IF

  ' Initialize the return variable with a default value of zero for any unhandled memory addresses
  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, "0"

  ' Create a jump label to bypass the numlock logic if the requested address is not exactly 1047
  skipLbl$ = tiraLabelCreateNew$("SKIP_PEEK")
  tiraJmpCond "JNE", arg1$, "1047", skipLbl$

  ' Ask windows for the actual state of the numlock key
  tiraCall "IAT_GETKEYSTATE", 1, "144"
  stateVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, stateVar$

  ' Mask out all but the lowest bit to get the clean toggle state
  tiraOp TC_AND, stateVar$, stateVar$, "1"

  ' Shift the bit left into the bit five position to emulate the legacy keyboard flag
  tiraOp TC_SHL, stateVar$, stateVar$, "5"

  ' Assign the emulated flag byte to the return variable
  tiraAssign resVar$, stateVar$

  tiraLabel skipLbl$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_PEEK$ = scratchName$

END FUNCTION ' parse_PEEK$

''''''''''''''''''''''''
FUNCTION parse_POKE (startIdx)

  ' This function evaluates the poke command to write data into memory
  ' Rather than exposing direct memory access which would crash a modern operating system
  ' we specifically look for address 1047. In legacy dos systems, address 1047 holds
  ' the keyboard flags where the bit representing 32 controls the numlock state
  ' If the user script tries to write to 1047, we extract the requested numlock state
  ' and use the windows api to simulate physical key presses if the state needs to change

  DIM commaIdx AS LONG
  DIM addrVar$
  DIM valVar$
  DIM skipLbl$
  DIM desired$
  DIM current$
  DIM endIdx AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  commaIdx = findComma(startIdx + 1, endIdx)
  IF commaIdx = 0 THEN
    throwCompilerError "POKE MISSING COMMA", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  ' Evaluate the address and value arguments provided by the user script
  addrVar$ = tiraParseExpressionInt$(startIdx + 1, commaIdx - 1, ALIM, "POKE ADDRESS MUST BE NUMERIC")
  IF addrVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  valVar$ = tiraParseExpressionInt$(commaIdx + 1, endIdx, ALIM, "POKE VALUE MUST BE NUMERIC")
  IF valVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  ' Create a jump label to skip the emulation block if the address is not exactly 1047
  skipLbl$ = tiraLabelCreateNew$("SKIP_POKE")
  tiraJmpCond "JNE", addrVar$, "1047", skipLbl$

  ' Extract the target state by masking out the thirty two bit and shifting it down to the lowest bit position
  desired$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, desired$, valVar$, "32"
  tiraOp TC_SHR, desired$, desired$, "5"

  ' Ask windows for the current hardware state of the numlock key using its virtual key code
  tiraCall "IAT_GETKEYSTATE", 1, "144"
  current$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, current$

  ' Mask the windows return value to isolate just the active toggle state bit
  tiraOp TC_AND, current$, current$, "1"

  ' Compare the requested state with the current hardware state and jump past the toggle event if they match
  tiraJmpCond "JE", desired$, current$, skipLbl$

  ' Fire down and up keyboard events to physically toggle the numlock key at the hardware level
  tiraCall "IAT_KEYBD_EVENT", 4, "144, 69, 1, 0"
  tiraCall "IAT_KEYBD_EVENT", 4, "144, 69, 3, 0"

  tiraLabel skipLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_POKE = 1

END FUNCTION ' parse_POKE

''''''''''''''''''''''''
FUNCTION parse_PRINT (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2
  origEndIdx = endIdx

  suppressNewline = 0
  IF endIdx >= startIdx + 1 THEN
    tVal = lineTokenVals(endIdx)

    SELECT CASE tVal

      CASE 256 + ASC(";"), 256 + ASC(",")
        suppressNewline = 1
        endIdx = endIdx - 1

    END SELECT ' tVal

  END IF

  tira_Start

  IF endIdx < startIdx + 1 THEN
    IF suppressNewline = 0 THEN
      tiraCall "RT_CRLF", 0, ""
    END IF
  ELSE
    itemStart = startIdx + 1
    DO WHILE itemStart <= endIdx
      itemEnd = endIdx
      parenDepth = 0
      FOR ii = itemStart TO endIdx
        tVal = lineTokenVals(ii)
        IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
        IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1
        IF parenDepth = 0 THEN
          IF tVal = 256 + ASC(";") OR tVal = 256 + ASC(",") THEN
            itemEnd = ii - 1
            EXIT FOR
          END IF
        END IF
      NEXT

      IF itemEnd >= itemStart THEN
        exprVar$ = tiraParseExpression$(itemStart, itemEnd, 1)
        IF exprVar$ = "" THEN
          tira_Cancel
          EXIT FUNCTION
        END IF

        IF exprIs.DataType = TYPE_STRING THEN
          tiraCall "RT_PRINT_STR", 1, exprVar$
        ELSE
          IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
            ' Safely promote Singles to Doubles for the RT_PRINT_FLOAT varargs requirement
            IF exprIs.DataType = TYPE_SINGLE THEN
              castVar$ = tiraDimVar$("T", TYPE_DOUBLE)
              tiraOp TC_CAST, castVar$, exprVar$, LTRIM$(STR$(TYPE_DOUBLE))
              exprVar$ = castVar$
            END IF
            tiraCall "RT_PRINT_FLOAT", 1, exprVar$
          ELSE
            tiraCall "RT_PRINT_INT", 1, exprVar$
          END IF
        END IF
      END IF

      itemStart = itemEnd + 2
    LOOP

    IF suppressNewline = 0 THEN
      tiraCall "RT_CRLF", 0, ""
    END IF
  END IF

  tira_EndAndProcess

  return2 origEndIdx
  parse_PRINT = 1

END FUNCTION ' parse_PRINT

''''''''''''''''''''''''
FUNCTION parse_PSET (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  comma1 = findComma(startIdx + 1, endIdx)
  comma2 = 0
  IF comma1 > 0 THEN
    comma2 = findComma(comma1 + 1, endIdx)
  END IF

  IF comma1 = 0 THEN
    throwCompilerError "PSET NEEDS X, Y, COLOR", ASIS, 0
    EXIT FUNCTION
  END IF

  coordStart = startIdx + 1
  IF comma2 = 0 THEN
    ' PSET (X, Y), Color
    coordEnd = comma1 - 1
    cStart = comma1 + 1
  ELSE
    ' PSET X, Y, Color
    coordEnd = comma2 - 1
    cStart = comma2 + 1
  END IF
  cEnd = endIdx

  cComma = retCoordinateBoundaries(coordStart, coordEnd)
  IF cComma = 0 THEN
    throwCompilerError "PSET NEEDS X, Y, COLOR", ASIS, 0
    EXIT FUNCTION
  END IF
  cStartCoord = returnedData2
  cEndCoord = returnedData3

  xStart = cStartCoord
  xEnd = cComma - 1
  yStart = cComma + 1
  yEnd = cEndCoord

  tira_Start

  xVar$ = tiraParseExpressionInt$(xStart, xEnd, ALIM, "COORDINATE MUST BE NUMERIC")
  IF xVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  yVar$ = tiraParseExpressionInt$(yStart, yEnd, ALIM, "COORDINATE MUST BE NUMERIC")
  IF yVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  cVar$ = tiraParseExpressionInt$(cStart, cEnd, ALIM, "COLOR MUST BE NUMERIC")
  IF cVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  skipLbl$ = tiraLabelCreateNew$("SKIP_PSET")

  ' Speed boost optimization: Unsigned JAE bounds check validates both < 0 and >= max simultaneously
  tiraJmpCond "JAE", xVar$, cTrNum$(gfxConfig.SizeX), skipLbl$

  ' Bounds check Y
  tiraJmpCond "JAE", yVar$, cTrNum$(gfxConfig.SizeY), skipLbl$

  ' Color masking to byte limit (255)
  cMask$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, cMask$, cVar$, "255"

  ' Offset calculation -- (Y * Width) + X
  offsetVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, offsetVar$, yVar$, cTrNum$(gfxConfig.SizeX)
  tiraOp TC_ADD, offsetVar$, offsetVar$, xVar$

  ' Grab Base Framebuffer Ptr directly from the User working backbuffer
  fbBase$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign fbBase$, "!G_FRAMEBUF_BACK_PTR"

  ' Target Address
  targetAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, targetAddr$, fbBase$, offsetVar$

  ' Write Pixel
  tiraWriteMem targetAddr$, cMask$, "1"

  ' Off-screen boundary jump lands here
  tiraLabel skipLbl$

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  ' Instruct backend to refresh invalid rect region using the thread-safe double buffering routine
  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tira_EndAndProcess

  return2 endIdx
  parse_PSET = 1

END FUNCTION ' parse_PSET

''''''''''''''''''''''''
FUNCTION parse_PUT (startIdx)

  DIM comma1 AS LONG
  DIM comma2 AS LONG
  DIM cComma AS LONG
  DIM isFileIO AS LONG
  DIM cStart AS LONG
  DIM cEnd AS LONG
  DIM tokIdx AS LONG
  DIM closeParen AS LONG
  DIM arrComma AS LONG
  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM statElems AS LONG
  DIM fixedLen AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  comma1 = findComma(startIdx + 1, endIdx)

  cComma = 0
  IF comma1 > 0 THEN
    cComma = retCoordinateBoundaries(startIdx + 1, comma1 - 1)
  END IF

  isFileIO = 0
  IF cComma = 0 THEN
    isFileIO = 1
  END IF

  IF isFileIO = 1 THEN
    parse_PUT = parse_PUT_File(startIdx, endIdx)
    EXIT FUNCTION
  END IF

  IF compileHasGraphics = 0 THEN
    throwCompilerError "GRAPHICS PUT REQUIRES #GRAPHICS", ASIS, 0
    EXIT FUNCTION
  END IF

  IF comma1 = 0 THEN
    throwCompilerError "PUT MISSING ARRAY VARIABLE", ASIS, 0
    EXIT FUNCTION
  END IF

  cComma = retCoordinateBoundaries(startIdx + 1, comma1 - 1)
  IF cComma = 0 THEN
    throwCompilerError "PUT MISSING X, Y", ASIS, 0
    EXIT FUNCTION
  END IF
  cStart = returnedData2
  cEnd = returnedData3

  tira_Start

  x$ = tiraParseExpressionInt$(cStart, cComma - 1, ALIM, "COORDINATE MUST BE NUMERIC")
  IF x$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  y$ = tiraParseExpressionInt$(cComma + 1, cEnd, ALIM, "COORDINATE MUST BE NUMERIC")
  IF y$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  comma2 = findComma(comma1 + 1, endIdx)

  IF comma2 = 0 THEN
    throwCompilerError "PUT MISSING ACTION (PSET)", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF

  tokIdx = comma1 + 1
  vTok$ = lineTokens$(tokIdx)
  vName$ = UCASE$(vTok$)
  ff = resolveSymbol(vName$)
  IF ff = 0 THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  vIdx = returnedData2

  IF symbols(vIdx).IsArray = 0 THEN
    throwCompilerError "PUT TARGET MUST BE AN ARRAY", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF

  arrX$ = ""
  arrY$ = ""

  tokIdx = tokIdx + 1
  IF tokIdx < comma2 THEN
    IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
      ff = findMatchingParen(tokIdx, comma2 - 1)
      IF ff = 1 THEN
        closeParen = returnedData2
        arrComma = findComma(tokIdx + 1, closeParen - 1)
        IF arrComma > 0 THEN
          arrX$ = tiraParseExpressionInt$(tokIdx + 1, arrComma - 1, 0, "INDEX MUST BE NUMERIC")
          arrY$ = tiraParseExpressionInt$(arrComma + 1, closeParen - 1, 0, "INDEX MUST BE NUMERIC")
        ELSE
          arrX$ = tiraParseExpressionInt$(tokIdx + 1, closeParen - 1, 0, "INDEX MUST BE NUMERIC")
        END IF
      END IF
    END IF
  END IF

  ptr$ = tiraFrontendCalcAddress$(vName$, arrX$, arrY$, 0)
  IF ptr$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  actualName$ = RTRIM$(symbols(vIdx).RecordName)
  dt = symbols(vIdx).DataType
  elemSize = 8

  SELECT CASE dt
    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
    CASE TYPE_STRING
      fixedLen = retFixedStringLength(vIdx)
      IF fixedLen > 0 THEN elemSize = fixedLen ELSE elemSize = 8
    CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
  END SELECT

  totalElems$ = tiraDimVar$("T", TYPE_LONG)

  IF symbols(vIdx).IsArray = 1 THEN
    statElems = symbols(vIdx).Size
    IF symbols(vIdx).Size2 > 0 THEN statElems = statElems * symbols(vIdx).Size2
    tiraAssign totalElems$, LTRIM$(STR$(statElems))
  ELSE
    tiraAssign totalElems$, "!G_SYS_" + actualName$ + "_AX_VAL"
    IF symbols(vIdx).Size2 > 0 THEN
      tiraOp TC_MUL, totalElems$, totalElems$, "!G_SYS_" + actualName$ + "_AY_VAL"
    END IF
  END IF

  safeElems$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_CAST, safeElems$, totalElems$, LTRIM$(STR$(TYPE_INTEGER64))

  byteSize$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_MUL, byteSize$, safeElems$, LTRIM$(RTRIM$(STR$(elemSize)))

  baseAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  IF symbols(vIdx).IsArray = 2 THEN
    tiraNew TC_READ_MEM, baseAddr$ + ", " + actualName$
  ELSE
    tiraOp TC_ADDRESS_OF, baseAddr$, actualName$, ""
  END IF

  endPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, endPtr$, baseAddr$, byteSize$

  IF lineTokenVals(comma2 + 1) <> TOK_PSET THEN
    throwCompilerError "ONLY PSET SUPPORTED FOR PUT", ASIS, 0
    tira_Cancel
    EXIT FUNCTION
  END IF

  tiraCall "RT_PUT", 4, x$ + ", " + y$ + ", " + ptr$ + ", " + endPtr$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_PUT = 1

END FUNCTION ' parse_PUT

''''''''''''''''''''''''
FUNCTION parse_PUT_File (startIdx, endIdx)

  DIM comma1 AS LONG
  DIM comma2 AS LONG
  DIM targetStart AS LONG
  DIM closeParen AS LONG
  DIM arrComma AS LONG
  DIM tokIdx AS LONG
  DIM vTok$, vName$
  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM fixedLen AS LONG

  DIM hasArrayIndices AS LONG

  tokIdx = startIdx + 1
  IF lineTokens$(tokIdx) = "#" THEN
    tokIdx = tokIdx + 1
  ELSE
    IF LEFT$(lineTokens$(tokIdx), 1) = "#" THEN
      lineTokens$(tokIdx) = MID$(lineTokens$(tokIdx), 2)
    END IF
  END IF

  comma1 = findComma(tokIdx, endIdx)
  IF comma1 = 0 THEN
    throwCompilerError "PUT MISSING COMMA", ASIS, 0
    EXIT FUNCTION
  END IF

  comma2 = findComma(comma1 + 1, endIdx)
  IF comma2 = 0 THEN
    targetStart = comma1 + 1
  ELSE
    targetStart = comma2 + 1
  END IF

  IF targetStart > endIdx THEN
    throwCompilerError "PUT MISSING TARGET VARIABLE", ASIS, 0
    EXIT FUNCTION
  END IF

  vTok$ = lineTokens$(targetStart)
  vName$ = UCASE$(vTok$)
  ff = resolveSymbol(vName$)
  IF ff = 0 THEN EXIT FUNCTION
  vIdx = returnedData2

  tira_Start

  fileNumVar$ = tiraParseExpressionInt$(tokIdx, comma1 - 1, ALIM, "FILE NUM MUST BE NUMERIC")
  IF fileNumVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  xVar$ = ""
  yVar$ = ""
  hasArrayIndices = 0

  IF targetStart < endIdx THEN
    IF lineTokenVals(targetStart + 1) = 256 + ASC("(") THEN
      hasArrayIndices = 1
      ff = findMatchingParen(targetStart + 1, endIdx)
      IF ff = 1 THEN
        closeParen = returnedData2
        arrComma = findComma(targetStart + 2, closeParen - 1)
        IF arrComma > 0 THEN
          xVar$ = tiraParseExpressionInt$(targetStart + 2, arrComma - 1, ALIM, "INDEX MUST BE NUMERIC")
          yVar$ = tiraParseExpressionInt$(arrComma + 1, closeParen - 1, ALIM, "INDEX MUST BE NUMERIC")
        ELSE
          xVar$ = tiraParseExpressionInt$(targetStart + 2, closeParen - 1, ALIM, "INDEX MUST BE NUMERIC")
        END IF

        IF xVar$ = "" OR (arrComma > 0 AND yVar$ = "") THEN
          tira_Cancel
          EXIT FUNCTION
        END IF
      ELSE
        throwCompilerError "MISSING )", ASIS, 0
        tira_Cancel
        EXIT FUNCTION
      END IF
    END IF
  END IF

  baseArr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, baseArr$, "!G_LAYOUT_FILE_HANDLES_ARR", ""

  slotAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraLeaSIB slotAddr$, baseArr$, fileNumVar$, "8"

  handleVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, handleVar$ + ", " + slotAddr$

  skipFileIOLbl$ = tiraLabelCreateNew$("SKIP_FILE_IO")

  tiraJmpCond "JE", handleVar$, "0", skipFileIOLbl$
  tiraJmpCond "JE", handleVar$, "-1", skipFileIOLbl$

  ptr$ = tiraFrontendCalcAddress$(vName$, xVar$, yVar$, 0)
  IF ptr$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  dt = symbols(vIdx).DataType
  elemSize = 8

  SELECT CASE dt

    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
    CASE TYPE_STRING:
      fixedLen = retFixedStringLength(vIdx)
      IF fixedLen > 0 THEN elemSize = fixedLen ELSE elemSize = 8
    CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize

  END SELECT ' dt

  dataSize$ = tiraDimVar$("T", TYPE_LONG)
  dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)

  IF dt = TYPE_STRING AND fixedLen = 0 THEN
    descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)

    IF symbols(vIdx).IsArray > 0 THEN
      tiraNew TC_READ_MEM, descPtr$ + ", " + ptr$
    ELSE
      tiraAssign descPtr$, ptr$
    END IF

    tiraJmpCond "JE", descPtr$, "0", skipFileIOLbl$

    tiraAssign dataSize$, tiraGetStringLen$(descPtr$)
    tiraAssign dataPtr$, tiraGetStringData$(descPtr$)

    tiraJmpCond "JLE", dataSize$, "0", skipFileIOLbl$
    tiraJmpCond "JE", dataPtr$, "0", skipFileIOLbl$

  ELSE
    IF dt = TYPE_STRING AND fixedLen > 0 THEN
      tiraAssign dataSize$, LTRIM$(STR$(fixedLen))

      IF symbols(vIdx).IsArray > 0 THEN
        tiraAssign dataPtr$, ptr$
      ELSE
        descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
        tiraAssign descPtr$, ptr$

        tiraJmpCond "JE", descPtr$, "0", skipFileIOLbl$

        tiraAssign dataPtr$, tiraGetStringData$(descPtr$)
        tiraJmpCond "JE", dataPtr$, "0", skipFileIOLbl$
      END IF
    ELSE
      tiraAssign dataSize$, LTRIM$(STR$(elemSize))
      tiraAssign dataPtr$, ptr$

      tiraJmpCond "JLE", dataSize$, "0", skipFileIOLbl$
    END IF
  END IF

  numWrt$ = tiraDimVar$("T", TYPE_LONG)
  numWrtPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, numWrtPtr$, numWrt$, ""

  tiraCall "IAT_WRITEFILE", 5, handleVar$ + ", " + dataPtr$ + ", " + dataSize$ + ", " + numWrtPtr$ + ", 0"

  tiraLabel skipFileIOLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_PUT_File = 1

END FUNCTION ' parse_PUT_File

''''''''''''''''''''''''
FUNCTION parse_ON (startIdx)

  ' Start searching for the instruction end at the label token (startIdx + 3) to prevent
  ' findInstructionEnd from incorrectly splitting the statement on the GOTO keyword
  ff = findInstructionEnd(startIdx + 3)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx >= startIdx + 3 THEN
    IF lineTokenVals(startIdx + 1) = TOK_ERROR THEN
      IF lineTokenVals(startIdx + 2) = TOK_GOTO THEN
        ff = verifyNoExtraTokens(endIdx, startIdx + 3, "ON ERROR GOTO")
        IF ff = 0 THEN EXIT FUNCTION

        lblTok$ = lineTokens$(startIdx + 3)

        tira_Start

        IF lblTok$ <> "0" THEN
          lblName$ = "%" + UCASE$(lblTok$)
          ff = resolveSymbol(lblName$)
          IF ff = 0 THEN
            tira_Cancel
            EXIT FUNCTION
          END IF

          tiraOp TC_ADDRESS_OF, "!G_SYS_ERR_HANDLER_PTR", lblName$, ""
        ELSE
          tiraAssign "!G_SYS_ERR_HANDLER_PTR", "0"
        END IF

        tiraScheduleHeapReset
        tira_EndAndProcess

        return2 endIdx
        parse_ON = 1
        EXIT FUNCTION
      END IF
    END IF
  END IF

  throwCompilerError "UNSUPPORTED OR MALFORMED ON STATEMENT", ASIS, 0

END FUNCTION ' parse_ON

''''''''''''''''''''''''
FUNCTION parse_OPEN (startIdx)

  DIM hasFor AS LONG
  DIM forIdx AS LONG
  DIM asIdx AS LONG
  DIM fileNameStart AS LONG
  DIM fileNameEnd AS LONG
  DIM fileNumStart AS LONG
  DIM fileNameVar$
  DIM fileNumVar$
  DIM tokVal AS LONG
  DIM accessVal$
  DIM dispVal$
  DIM strDataPtr$
  DIM argList$
  DIM handleVar$
  DIM baseArr$
  DIM slotAddr$

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  hasFor = 0
  forIdx = 0
  ff = findNextTokenAtDepth0(startIdx + 1, endIdx, TOK_FOR)
  IF ff = 1 THEN
    hasFor = 1
    forIdx = returnedData2
  END IF

  asIdx = 0
  ff = findNextTokenAtDepth0(startIdx + 1, endIdx, TOK_AS)
  IF ff = 1 THEN
    asIdx = returnedData2
  ELSE
    throwCompilerError "OPEN MISSING AS", ASIS, 0
    EXIT FUNCTION
  END IF

  fileNameStart = startIdx + 1
  fileNameEnd = asIdx - 1
  IF hasFor = 1 THEN fileNameEnd = forIdx - 1

  IF hasFor = 1 THEN
    IF forIdx + 1 < asIdx THEN
      tokVal = lineTokenVals(forIdx + 1)
      SELECT CASE tokVal
        CASE TOK_BINARY, TOK_RANDOM
        CASE ELSE
          throwCompilerError "INVALID FILE MODE (ONLY BINARY/RANDOM SUPPORTED)", ASIS, 0
          EXIT FUNCTION
      END SELECT
    ELSE
      throwCompilerError "OPEN MISSING MODE AFTER FOR", ASIS, 0
      EXIT FUNCTION
    END IF
  END IF

  fileNumStart = asIdx + 1
  IF fileNumStart <= endIdx THEN
    ' Strip the # symbol so the expression evaluates properly
    IF lineTokens$(fileNumStart) = "#" THEN
      fileNumStart = fileNumStart + 1
    ELSE
      IF LEFT$(lineTokens$(fileNumStart), 1) = "#" THEN
        lineTokens$(fileNumStart) = MID$(lineTokens$(fileNumStart), 2)
      END IF
    END IF
  END IF

  tira_Start

  fileNameVar$ = tiraParseExpression$(fileNameStart, fileNameEnd, ALIM)
  IF fileNameVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "FILENAME MUST BE STRING", ASIS, 0
    EXIT FUNCTION
  END IF

  fileNumVar$ = tiraParseExpressionInt$(fileNumStart, endIdx, ALIM, "FILENUM MUST BE NUMERIC")
  IF fileNumVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  ' Setup generic OS constants mapping to the required behavior natively to bypass CPU register constraints
  accessVal$ = "-1073741824" ' GENERIC_READ OR GENERIC_WRITE
  dispVal$ = "4" ' OPEN_ALWAYS

  ' String arrays naturally track null terminators so it resolves seamlessly here to map directly into OS requirements
  strDataPtr$ = tiraGetStringData$(fileNameVar$)

  ' Execute the CreateFileA procedure and allow the OS to perform file locking tracking
  ' ShareMode = 3 (FILE_SHARE_READ OR FILE_SHARE_WRITE)
  argList$ = strDataPtr$ + ", " + accessVal$ + ", 3, 0, " + dispVal$ + ", 128, 0"
  tiraCall "IAT_CREATEFILEA", 7, argList$

  handleVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_GET_RET, handleVar$

  ' Push OS Pointer Handle directly into the corresponding layout array index utilizing the provided File Number
  baseArr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADDRESS_OF, baseArr$, "!G_LAYOUT_FILE_HANDLES_ARR", ""

  slotAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraLeaSIB slotAddr$, baseArr$, fileNumVar$, "8"

  tiraWriteMem slotAddr$, handleVar$, "8"

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_OPEN = 1

END FUNCTION ' parse_OPEN

''''''''''''''''''''''''
FUNCTION parse_PALETTE (startIdx)

  DIM comma1 AS LONG
  DIM idxVar$
  DIM colorVar$
  DIM mappedColor$
  DIM skipLbl$
  DIM palDescPtr$
  DIM palDataAddr$
  DIM srcOffsetVar$
  DIM srcAddr$
  DIM destOffsetVar$
  DIM destAddr$
  DIM colorVal$
  DIM skipAutoLbl$

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    return2 endIdx
    parse_PALETTE = 1
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 1, endIdx)

  IF comma1 = 0 THEN
    throwCompilerError "PALETTE REQUIRES 2 ARGUMENTS", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  idxVar$ = tiraParseExpressionInt$(startIdx + 1, comma1 - 1, ALIM, "PALETTE INDEX MUST BE NUMERIC")
  IF idxVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  colorVar$ = tiraParseExpressionInt$(comma1 + 1, endIdx, ALIM, "COLOR VALUE MUST BE NUMERIC")
  IF colorVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  skipLbl$ = tiraLabelCreateNew$("SKIP_PAL")

  tiraJmpCond "JL", idxVar$, "0", skipLbl$
  tiraJmpCond "JG", idxVar$, "255", skipLbl$

  ' Mask the source color to 0-15 to map EGA colors to our standard VGA palette block
  mappedColor$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, mappedColor$, colorVar$, "15"

  palDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign palDescPtr$, "!G_GFX_PALETTE_DESC$"

  palDataAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, palDataAddr$ + ", " + palDescPtr$

  srcOffsetVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_MUL, srcOffsetVar$, mappedColor$, "4"

  srcAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, srcAddr$, palDataAddr$, srcOffsetVar$

  destOffsetVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_MUL, destOffsetVar$, idxVar$, "4"

  destAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, destAddr$, palDataAddr$, destOffsetVar$

  colorVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM, colorVal$ + ", " + srcAddr$

  tiraWriteMem destAddr$, colorVal$, "4"

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraLabel skipLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_PALETTE = 1

END FUNCTION ' parse_PALETTE

''''''''''''''''''''''''
FUNCTION parse_PALETTECOLOR (startIdx)

  DIM comma1 AS LONG
  DIM idxVar$
  DIM colorVar$
  DIM skipLbl$
  DIM palDescPtr$
  DIM palDataAddr$
  DIM offsetVar$
  DIM targetAddr$
  DIM skipAutoLbl$

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  comma1 = findComma(startIdx + 1, endIdx)

  IF comma1 = 0 THEN
    throwCompilerError "_PALETTECOLOR REQUIRES 2 ARGUMENTS", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  idxVar$ = tiraParseExpressionInt$(startIdx + 1, comma1 - 1, ALIM, "PALETTE INDEX MUST BE NUMERIC")
  IF idxVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  colorVar$ = tiraParseExpressionInt$(comma1 + 1, endIdx, ALIM, "COLOR VALUE MUST BE NUMERIC")
  IF colorVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  skipLbl$ = tiraLabelCreateNew$("SKIP_PAL")

  tiraJmpCond "JL", idxVar$, "0", skipLbl$
  tiraJmpCond "JG", idxVar$, "255", skipLbl$

  palDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign palDescPtr$, "!G_GFX_PALETTE_DESC$"

  palDataAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, palDataAddr$ + ", " + palDescPtr$

  offsetVar$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_MUL, offsetVar$, idxVar$, "4"

  targetAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, targetAddr$, palDataAddr$, offsetVar$

  tiraWriteMem targetAddr$, colorVar$, "4"

  tiraAssign "!G_GFX_DISPLAYI_PENDING_FLAG", "1"

  skipAutoLbl$ = tiraLabelCreateNew$("SKIP_AUTO")
  tiraJmpCond "JE", "!G_GFX_AUTODISPLAY_FLAG", "0", skipAutoLbl$
  tiraInjectPendingDisplayFlush
  tiraLabel skipAutoLbl$

  tiraLabel skipLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_PALETTECOLOR = 1

END FUNCTION ' parse_PALETTECOLOR

''''''''''''''''''''''''
FUNCTION parse_POINT$ (startIdx, endIdx, allowImplicit)

  DIM comma1 AS LONG
  DIM arg1$
  DIM arg2$
  DIM scratchName$
  DIM resVar$
  DIM skipLbl$
  DIM offsetVar$
  DIM targetAddr$
  DIM colorByte$
  DIM lblX$
  DIM lblY$
  DIM lblEnd$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED POINT", ASIS, 0
    parse_POINT$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED POINT", ASIS, 0
    parse_POINT$ = ""
    EXIT FUNCTION
  END IF

  IF compileHasGraphics = 0 THEN
    throwCompilerError "POINT REQUIRES #GRAPHICS", ASIS, 0
    parse_POINT$ = ""
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 2, endIdx - 1)

  tira_Start

  scratchName$ = tiraResolveHoistVar$("POINT", "_VAL")
  IF scratchName$ = "" THEN
    parse_POINT$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, "-1"

  IF comma1 = 0 THEN
    ' 1 argument: POINT(n)
    IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
    arg1$ = tiraParseExpressionInt$(startIdx + 2, endIdx - 1, allowImplicit, "POINT ARGUMENT MUST BE NUMERIC")
    IF arg1$ = "" THEN
      tira_Cancel
      parse_POINT$ = ""
      EXIT FUNCTION
    END IF

    lblX$ = tiraLabelCreateNew$("PT_X")
    lblY$ = tiraLabelCreateNew$("PT_Y")
    lblEnd$ = tiraLabelCreateNew$("PT_END")

    tiraJmpCond "JE", arg1$, "0", lblX$
    tiraJmpCond "JE", arg1$, "2", lblX$
    tiraJmpCond "JE", arg1$, "1", lblY$
    tiraJmpCond "JE", arg1$, "3", lblY$
    tiraJmp lblEnd$

    tiraLabel lblX$
    tiraAssign resVar$, "!G_GFX_CUR_X_VAL"
    tiraJmp lblEnd$

    tiraLabel lblY$
    tiraAssign resVar$, "!G_GFX_CUR_Y_VAL"
    tiraLabel lblEnd$

  ELSE
    ' 2 arguments: POINT(x, y)
    IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
    arg1$ = tiraParseExpressionInt$(startIdx + 2, comma1 - 1, allowImplicit, "COORDINATE MUST BE NUMERIC")
    IF arg1$ = "" THEN
      tira_Cancel
      parse_POINT$ = ""
      EXIT FUNCTION
    END IF

    IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
    arg2$ = tiraParseExpressionInt$(comma1 + 1, endIdx - 1, allowImplicit, "COORDINATE MUST BE NUMERIC")
    IF arg2$ = "" THEN
      tira_Cancel
      parse_POINT$ = ""
      EXIT FUNCTION
    END IF

    skipLbl$ = tiraLabelCreateNew$("PT_SKIP")

    ' Speed boost optimization: Unsigned JAE bounds check validates both < 0 and >= max simultaneously
    tiraJmpCond "JAE", arg1$, cTrNum$(gfxConfig.SizeX), skipLbl$
    tiraJmpCond "JAE", arg2$, cTrNum$(gfxConfig.SizeY), skipLbl$

    offsetVar$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_MUL, offsetVar$, arg2$, cTrNum$(gfxConfig.SizeX)
    tiraOp TC_ADD, offsetVar$, offsetVar$, arg1$

    targetAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, targetAddr$, "!G_FRAMEBUF_BACK_PTR", offsetVar$

    colorByte$ = tiraDimVar$("T", TYPE_UBYTE)
    tiraNew TC_READ_MEM, colorByte$ + ", " + targetAddr$

    tiraAssign resVar$, colorByte$

    tiraLabel skipLbl$
  END IF

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_POINT$ = scratchName$

END FUNCTION ' parse_POINT$

''''''''''''''''''''''''
FUNCTION parse_RANDOMIZE (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "EXPECTED NUMERIC ARGUMENT AFTER RANDOMIZE", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  argVar$ = tiraParseExpressionInt$(startIdx + 1, endIdx, ALIM, "RANDOMIZE REQUIRES NUMERIC ARGUMENT")
  IF argVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  tiraCall "IAT_SRAND", 1, argVar$

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_RANDOMIZE = 1

END FUNCTION ' parse_RANDOMIZE

''''''''''''''''''''''''
FUNCTION parse_READ (startIdx)

  DIM itemStart AS LONG
  DIM itemEnd AS LONG
  DIM commaIdx AS LONG
  DIM tokIdx AS LONG
  DIM closeParen AS LONG
  DIM arrComma AS LONG
  DIM vTok$, vName$
  DIM vIdx AS LONG
  DIM hasIndex AS LONG
  DIM arrX$, arrY$
  DIM hasField AS LONG
  DIM udtOffset AS LONG
  DIM fieldName$
  DIM uIdx AS LONG
  DIM fieldFound AS LONG
  DIM iField AS LONG
  DIM ptr$
  DIM targetType AS LONG
  DIM isStrVar AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "READ MISSING VARIABLES", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  itemStart = startIdx + 1
  DO WHILE itemStart <= endIdx
    itemEnd = endIdx
    commaIdx = findComma(itemStart, endIdx)
    IF commaIdx > 0 THEN itemEnd = commaIdx - 1

    tokIdx = itemStart
    vTok$ = lineTokens$(tokIdx)
    vName$ = UCASE$(vTok$)
    ff = resolveSymbol(vName$)
    IF ff = 0 THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
    vIdx = returnedData2
    targetType = symbols(vIdx).DataType

    tokIdx = tokIdx + 1

    hasIndex = 0
    arrX$ = ""
    arrY$ = ""
    IF tokIdx <= itemEnd THEN
      IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
        hasIndex = 1
        ff = findMatchingParen(tokIdx, itemEnd)
        IF ff = 1 THEN
          closeParen = returnedData2
          arrComma = findComma(tokIdx + 1, closeParen - 1)
          IF arrComma > 0 THEN
            arrX$ = tiraParseExpressionInt$(tokIdx + 1, arrComma - 1, 0, "INDEX MUST BE NUMERIC")
            arrY$ = tiraParseExpressionInt$(arrComma + 1, closeParen - 1, 0, "INDEX MUST BE NUMERIC")
          ELSE
            arrX$ = tiraParseExpressionInt$(tokIdx + 1, closeParen - 1, 0, "INDEX MUST BE NUMERIC")
          END IF
          tokIdx = closeParen + 1
        ELSE
          throwCompilerError "MISSING )", ASIS, 0
          tira_Cancel
          EXIT FUNCTION
        END IF
      END IF
    END IF

    hasField = 0
    udtOffset = 0
    IF tokIdx <= itemEnd THEN
      IF lineTokenVals(tokIdx) = 256 + ASC(".") THEN
        hasField = 1
        tokIdx = tokIdx + 1
        fieldName$ = UCASE$(lineTokens$(tokIdx))
        tokIdx = tokIdx + 1

        IF symbols(vIdx).DataType <> TYPE_UDT THEN
          throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
          tira_Cancel
          EXIT FUNCTION
        END IF

        uIdx = symbols(vIdx).UDTIndex
        fieldFound = 0
        FOR iField = 0 TO udts(uIdx).FieldCount - 1
          IF RTRIM$(udtFields(uIdx, iField).FieldName) = fieldName$ THEN
            udtOffset = udtFields(uIdx, iField).Offset
            targetType = udtFields(uIdx, iField).DataType
            fieldFound = 1
            EXIT FOR
          END IF
        NEXT

        IF fieldFound = 0 THEN
          throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
          tira_Cancel
          EXIT FUNCTION
        END IF
      END IF
    END IF

    ptr$ = tiraFrontendCalcAddress$(vName$, arrX$, arrY$, udtOffset)
    IF ptr$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    isStrVar = 0
    IF targetType = TYPE_STRING THEN isStrVar = 1

    tiraCall "RT_READ", 3, ptr$ + ", " + cTrNum$(isStrVar) + ", " + cTrNum$(targetType)

    itemStart = itemEnd + 2
  LOOP

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_READ = 1

END FUNCTION ' parse_READ

''''''''''''''''''''''''
FUNCTION parse_REDIM (startIdx)

  DIM endIdx AS LONG
  DIM tokIdx AS LONG
  DIM isShared AS LONG
  DIM arrSize1 AS LONG
  DIM arrSize2 AS LONG
  DIM isArray AS LONG
  DIM parenStart AS LONG
  DIM parenEnd AS LONG
  DIM dim1Start AS LONG
  DIM dim1End AS LONG
  DIM dim2Start AS LONG
  DIM dim2End AS LONG
  DIM hasComma AS LONG
  DIM commaIdx AS LONG
  DIM hasTo1 AS LONG
  DIM to1Idx AS LONG
  DIM hasTo2 AS LONG
  DIM to2Idx AS LONG
  DIM evalStart1 AS LONG
  DIM evalStart2 AS LONG
  DIM isNum AS LONG
  DIM i_check AS LONG
  DIM vIdx AS LONG
  DIM fixedLen AS LONG
  DIM dtMapped AS LONG
  DIM axIdx AS LONG
  DIM ayIdx AS LONG
  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM totalElems AS LONG
  DIM allocSize AS LONG
  DIM baseArrayName$
  DIM typeData AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tokIdx = startIdx + 1
  isShared = 0

  IF tokIdx <= endIdx THEN
    IF lineTokenVals(tokIdx) = TOK_SHARED THEN
      isShared = 1
      tokIdx = tokIdx + 1
    END IF
  END IF

  IF endIdx < tokIdx THEN
    throwCompilerError "MALFORMED REDIM", ASIS, 0
    EXIT FUNCTION
  END IF

  tira_Start

  DO WHILE tokIdx <= endIdx
    aTok$ = lineTokens$(tokIdx)
    IF lineTokenVals(tokIdx) <> 0 THEN
      throwCompilerErrorAndCancelTira "EXPECTED IDENTIFIER", ASIS, 0
      EXIT FUNCTION
    END IF

    tokIdx = tokIdx + 1

    arrSize1 = 1
    arrSize2 = 0
    isArray = 2 ' REDIM always maps to dynamically allocated arrays

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
        parenStart = tokIdx

        ff = findMatchingParen(parenStart, endIdx)
        IF ff = 0 THEN
          throwCompilerErrorAndCancelTira "MALFORMED ARRAY DIMENSION", ASIS, 0
          EXIT FUNCTION
        END IF
        parenEnd = returnedData2

        tokIdx = parenStart + 1

        commaIdx = findComma(tokIdx, parenEnd - 1)
        IF commaIdx > 0 THEN hasComma = 1 ELSE hasComma = 0

        '''' Dimension 1
        dim1Start = tokIdx
        IF hasComma = 1 THEN dim1End = commaIdx - 1 ELSE dim1End = parenEnd - 1

        hasTo1 = 0
        to1Idx = 0
        ff = findNextTokenAtDepth0(dim1Start, dim1End, TOK_TO)
        IF ff = 1 THEN
          hasTo1 = 1
          to1Idx = returnedData2
        END IF

        evalStart1 = dim1Start
        IF hasTo1 = 1 THEN evalStart1 = to1Idx + 1

        IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
        dynAxVar$ = tiraParseExpressionInt$(evalStart1, dim1End, ALIM, "ARRAY DIM MUST BE NUMERIC")
        IF dynAxVar$ = "" THEN
          tira_Cancel
          EXIT FUNCTION
        END IF

        dynAxVarTotal$ = tiraDimVar$("T", TYPE_LONG)
        tiraOp TC_ADD, dynAxVarTotal$, dynAxVar$, "1"

        sizeTok$ = ""
        FOR ii = evalStart1 TO dim1End
          sizeTok$ = sizeTok$ + retTokenText$(lineTokens$(ii))
        NEXT
        sizeTok$ = evalMathConst$(sizeTok$)

        isNum = 1
        FOR i_check = 1 TO LEN(sizeTok$)
          chCheck$ = MID$(sizeTok$, i_check, 1)
          IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN
            isNum = 0
            EXIT FOR
          END IF
        NEXT
        IF isNum = 0 OR sizeTok$ = "" THEN
          arrSize1 = 0
        ELSE
          arrSize1 = VAL(sizeTok$) + 1
        END IF

        '''' Dimension 2
        arrSize2 = 0
        dynAyVarTotal$ = tiraDimVar$("T", TYPE_LONG)
        tiraAssign dynAyVarTotal$, "0"

        IF hasComma = 1 THEN
          dim2Start = commaIdx + 1
          dim2End = parenEnd - 1

          hasTo2 = 0
          to2Idx = 0
          ff = findNextTokenAtDepth0(dim2Start, dim2End, TOK_TO)
          IF ff = 1 THEN
            hasTo2 = 1
            to2Idx = returnedData2
          END IF

          evalStart2 = dim2Start
          IF hasTo2 = 1 THEN evalStart2 = to2Idx + 1

          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          dynAyVar$ = tiraParseExpressionInt$(evalStart2, dim2End, ALIM, "ARRAY DIM MUST BE NUMERIC")
          IF dynAyVar$ = "" THEN
            tira_Cancel
            EXIT FUNCTION
          END IF

          tiraOp TC_ADD, dynAyVarTotal$, dynAyVar$, "1"

          sizeTok2$ = ""
          FOR ii = evalStart2 TO dim2End
            sizeTok2$ = sizeTok2$ + retTokenText$(lineTokens$(ii))
          NEXT
          sizeTok2$ = evalMathConst$(sizeTok2$)

          isNum = 1
          FOR i_check = 1 TO LEN(sizeTok2$)
            chCheck$ = MID$(sizeTok2$, i_check, 1)
            IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN
              isNum = 0
              EXIT FOR
            END IF
          NEXT
          IF isNum = 0 OR sizeTok2$ = "" THEN
            arrSize2 = 0
          ELSE
            arrSize2 = VAL(sizeTok2$) + 1
          END IF
        END IF

        tokIdx = parenEnd + 1
      ELSE
        throwCompilerErrorAndCancelTira "REDIM REQUIRES DIMENSIONS", ASIS, 0
        EXIT FUNCTION
      END IF
    ELSE
      throwCompilerErrorAndCancelTira "REDIM REQUIRES DIMENSIONS", ASIS, 0
      EXIT FUNCTION
    END IF

    vName$ = UCASE$(aTok$)
    ff = resolveSymbol(vName$)
    IF ff = 0 THEN
      tira_Cancel
      EXIT FUNCTION
    END IF
    vIdx = returnedData2

    ' Catch instances where the array was already established as STATIC via DIM and throw cleanly
    IF symbols(vIdx).IsArray = 1 THEN
      IF isDummyPass = 1 THEN
        throwCompilerErrorAndCancelTira "ARRAY ALREADY DIMMED AS STATIC", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF

    symbols(vIdx).IsArray = isArray
    symbols(vIdx).IsExplicit = 1
    IF isShared = 1 THEN symbols(vIdx).IsShared = 1

    IF arrSize2 > 0 THEN
      symbols(vIdx).Size = arrSize1 * arrSize2
      symbols(vIdx).Size2 = arrSize2
    ELSE
      symbols(vIdx).Size = arrSize1
      symbols(vIdx).Size2 = 0
    END IF

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = TOK_AS THEN
        tokIdx = tokIdx + 1
        tokIdx = parseTypeClause(tokIdx, endIdx)
        dtMapped = returnedData2
        typeData = returnedData3

        IF dtMapped = TYPE_UNDEFINED THEN
          tira_Cancel
          EXIT FUNCTION
        END IF

        symbols(vIdx).DataType = dtMapped
        IF dtMapped = TYPE_UDT THEN
          symbols(vIdx).UDTIndex = typeData
        ELSE
          IF dtMapped = TYPE_STRING THEN
            fixedLen = typeData
            IF fixedLen > 0 THEN
              symbols(vIdx).FixedStrLen = fixedLen
              strVarData$(vIdx) = SPACE$(fixedLen)
            END IF
          END IF
        END IF
      END IF
    END IF

    baseArrayName$ = RTRIM$(symbols(vIdx).RecordName)
    ff = resolveSymbol("!G_SYS_" + baseArrayName$ + "_AX_VAL")
    IF ff = 1 THEN axIdx = returnedData2
    ff = resolveSymbol("!G_SYS_" + baseArrayName$ + "_AY_VAL")
    IF ff = 1 THEN ayIdx = returnedData2

    ' Assigning dynamic tracking variables via TIRA protects sizing natively
    tiraAssign RTRIM$(symbols(axIdx).RecordName), dynAxVarTotal$
    tiraAssign RTRIM$(symbols(ayIdx).RecordName), dynAyVarTotal$

    dt = symbols(vIdx).DataType
    elemSize = 8

    SELECT CASE dt
      CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
      CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
      CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
      CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
      CASE TYPE_STRING
        fixedLen = retFixedStringLength(vIdx)
        IF fixedLen > 0 THEN
          elemSize = fixedLen
        ELSE
          elemSize = 8
        END IF
      CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
    END SELECT ' dt

    elemSizeStr$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign elemSizeStr$, LTRIM$(STR$(elemSize))

    totalElems$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign totalElems$, dynAxVarTotal$

    skipYMul$ = tiraLabelCreateNew$("SKIP_YMUL")
    tiraJmpCond "JLE", dynAyVarTotal$, "0", skipYMul$
    tiraOp TC_MUL, totalElems$, totalElems$, dynAyVarTotal$
    tiraLabel skipYMul$

    allocSize$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_MUL, allocSize$, totalElems$, elemSizeStr$

    ' Since this is REDIM, free the previously allocated heap memory natively if it exists
    tiraScheduleArrayFree vIdx

    tiraCall "IAT_HEAPALLOC", 3, "!G_MEM_PROCESS_HEAP_PTR, 8, " + allocSize$
    arrPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_GET_RET, arrPtr$
    tiraAssign baseArrayName$, arrPtr$

    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
        tokIdx = tokIdx + 1
      ELSE
        throwCompilerErrorAndCancelTira "UNEXPECTED TOKEN AFTER REDIM", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF
  LOOP

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_REDIM = 1

END FUNCTION ' parse_REDIM

''''''''''''''''''''''''
FUNCTION parse_RESUME (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tira_Start
  tiraScheduleHeapReset
  tiraNew TC_RESUME, ""
  tira_EndAndProcess

  return2 endIdx
  parse_RESUME = 1

END FUNCTION ' parse_RESUME

''''''''''''''''''''''''
FUNCTION parse_RESTORE (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tira_Start

  IF endIdx < startIdx + 1 THEN
    tiraAssign "!G_SYS_DATA_PTR_VAL", "0"
  ELSE
    lblTok$ = lineTokens$(startIdx + 1)
    lblName$ = "%" + UCASE$(lblTok$)
    expectedSymType = TYPE_LABEL
    ff = resolveSymbol(lblName$)
    IF ff = 1 THEN
      vIdx = returnedData2
      idxVal = symbols(vIdx).DataIndex
      tiraAssign "!G_SYS_DATA_PTR_VAL", LTRIM$(STR$(idxVal))
    ELSE
      tira_Cancel
      EXIT FUNCTION
    END IF
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_RESTORE = 1

END FUNCTION ' parse_RESTORE

''''''''''''''''''''''''
FUNCTION parse_RETURN (startIdx)

  DIM vIdx AS LONG
  DIM targetType AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tira_Start

  IF endIdx >= startIdx + 1 THEN
    IF insideSub = 0 THEN
      throwCompilerErrorAndCancelTira "RETURN OUTSIDE SUB OR FUNCTION", ASIS, 0
      EXIT FUNCTION
    END IF

    IF insideSub <> 2 THEN
      throwCompilerErrorAndCancelTira "SUB CANNOT RETURN A VALUE", ASIS, 0
      EXIT FUNCTION
    END IF

    argVar$ = tiraParseExpression$(startIdx + 1, endIdx, ALIM)
    IF argVar$ = "" THEN
      tira_Cancel
      EXIT FUNCTION
    END IF

    ff = resolveSymbol(currentSubName$)
    IF ff = 1 THEN
      vIdx = returnedData2
      targetType = returnedData3

      IF targetType = TYPE_STRING THEN
        IF exprIs.DataType <> TYPE_STRING THEN
          throwCompilerErrorAndCancelTira "TYPE MISMATCH", ASIS, 0
          EXIT FUNCTION
        END IF
        tiraCall "RT_STR_ASSIGN", 2, currentSubName$ + ", " + argVar$
      ELSE
        IF exprIs.DataType = TYPE_STRING THEN
          throwCompilerErrorAndCancelTira "TYPE MISMATCH", ASIS, 0
          EXIT FUNCTION
        END IF
        tiraAssign currentSubName$, argVar$
      END IF
    END IF

    tiraScheduleHeapReset
    tiraJmp "@END_ROUTINE_" + currentSubName$

  ELSE
    ' GOSUB Return (no arguments)
    tgtPtrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    retAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)
    baseAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)

    tiraOp TC_SUB, "!G_SYS_GOSUB_IDX", "!G_SYS_GOSUB_IDX", "1"
    tiraOp TC_ADDRESS_OF, baseAddrVar$, "!G_SYS_GOSUB_ARR", ""
    tiraLeaSIB tgtPtrVar$, baseAddrVar$, "!G_SYS_GOSUB_IDX", "8"
    tiraNew TC_READ_MEM, retAddrVar$ + ", " + tgtPtrVar$
    tiraScheduleHeapReset
    tiraNew TC_JMP_DYN, retAddrVar$
  END IF

  tira_EndAndProcess

  return2 endIdx
  parse_RETURN = 1

END FUNCTION ' parse_RETURN

''''''''''''''''''''''''
FUNCTION parse_RGB32$ (startIdx, endIdx, allowImplicit)

  DIM argR$
  DIM argG$
  DIM argB$
  DIM comma1 AS LONG
  DIM comma2 AS LONG
  DIM scratchName$
  DIM maskR$
  DIM maskG$
  DIM maskB$
  DIM shiftG$
  DIM shiftR$
  DIM resVar$

  IF startIdx + 7 > endIdx THEN
    throwCompilerError "MALFORMED _RGB32", ASIS, 0
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED _RGB32", ASIS, 0
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 2, endIdx - 1)
  IF comma1 = 0 THEN
    throwCompilerError "_RGB32 REQUIRES 3 ARGUMENTS", ASIS, 0
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  comma2 = findComma(comma1 + 1, endIdx - 1)
  IF comma2 = 0 THEN
    throwCompilerError "_RGB32 REQUIRES 3 ARGUMENTS", ASIS, 0
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  argR$ = tiraParseExpressionInt$(startIdx + 2, comma1 - 1, allowImplicit, "_RGB32 RED ARG MUST BE NUMERIC")
  IF argR$ = "" THEN
    tira_Cancel
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  argG$ = tiraParseExpressionInt$(comma1 + 1, comma2 - 1, allowImplicit, "_RGB32 GREEN ARG MUST BE NUMERIC")
  IF argG$ = "" THEN
    tira_Cancel
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  argB$ = tiraParseExpressionInt$(comma2 + 1, endIdx - 1, allowImplicit, "_RGB32 BLUE ARG MUST BE NUMERIC")
  IF argB$ = "" THEN
    tira_Cancel
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("RGB32", "_VAL")
  IF scratchName$ = "" THEN
    parse_RGB32$ = ""
    EXIT FUNCTION
  END IF

  maskR$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, maskR$, argR$, "255"

  maskG$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, maskG$, argG$, "255"

  maskB$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, maskB$, argB$, "255"

  shiftG$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SHL, shiftG$, maskG$, "8"

  shiftR$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SHL, shiftR$, maskR$, "16"

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, resVar$, maskB$, shiftG$
  tiraOp TC_ADD, resVar$, resVar$, shiftR$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_RGB32$ = scratchName$

END FUNCTION ' parse_RGB32$

''''''''''''''''''''''''
FUNCTION parse_RIGHT$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM arg2$
  DIM scratchName$
  DIM srcPtr$
  DIM strLen$
  DIM srcOffset$
  DIM dataPtr$
  DIM descPtr$
  DIM comma1 AS LONG

  IF startIdx + 5 > endIdx THEN
    throwCompilerError "MALFORMED RIGHT$", ASIS, 0
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED RIGHT$", ASIS, 0
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF

  comma1 = findComma(startIdx + 2, endIdx - 1)

  IF comma1 = 0 THEN
    throwCompilerError "RIGHT$ REQUIRES TWO ARGUMENTS", ASIS, 0
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, comma1 - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF
  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "RIGHT$ ARG 1 MUST BE STRING", ASIS, 0
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  arg2$ = tiraParseExpressionInt$(comma1 + 1, endIdx - 1, allowImplicit, "RIGHT$ ARG 2 MUST BE NUMERIC")
  IF arg2$ = "" THEN
    tira_Cancel
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("RIGHT", "_DESC$")
  IF scratchName$ = "" THEN
    parse_RIGHT$ = ""
    EXIT FUNCTION
  END IF

  srcPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  tiraClamp arg2$, "0", strLen$

  srcOffset$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, srcOffset$, strLen$, arg2$
  tiraOp TC_ADD, srcPtr$, srcPtr$, srcOffset$

  tiraAssign strLen$, arg2$

  dataPtr$ = tiraAllocTempMem$(strLen$)

  tiraMemcpy dataPtr$, srcPtr$, strLen$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_RIGHT$ = scratchName$

END FUNCTION ' parse_RIGHT$

''''''''''''''''''''''''
FUNCTION parse_RTRIM$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM dataPtr$
  DIM strLen$
  DIM endPtr$
  DIM loopTop$
  DIM loopDone$
  DIM byteVal$
  DIM isSpaceLbl$
  DIM descPtr$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED RTRIM$", ASIS, 0
    parse_RTRIM$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED RTRIM$", ASIS, 0
    parse_RTRIM$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_RTRIM$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "RTRIM$ REQUIRES STRING ARGUMENT", ASIS, 0
    parse_RTRIM$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("RTRIM", "_DESC$")
  IF scratchName$ = "" THEN
    parse_RTRIM$ = ""
    EXIT FUNCTION
  END IF

  dataPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  endPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, endPtr$, dataPtr$, strLen$
  tiraOp TC_SUB, endPtr$, endPtr$, "1"

  loopTop$ = tiraLabelCreateNew$("RTRIM_LOOP")
  loopDone$ = tiraLabelCreateNew$("RTRIM_DONE")

  tiraLabel loopTop$
  tiraJmpCond "JLE", strLen$, "0", loopDone$

  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, byteVal$ + ", " + endPtr$

  isSpaceLbl$ = tiraLabelCreateNew$("RTRIM_IS_SPC")
  tiraJmpCond "JE", byteVal$, "32", isSpaceLbl$
  tiraJmpCond "JNE", byteVal$, "9", loopDone$
  tiraLabel isSpaceLbl$

  tiraOp TC_SUB, endPtr$, endPtr$, "1"
  tiraOp TC_SUB, strLen$, strLen$, "1"
  tiraJmp loopTop$

  tiraLabel loopDone$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_RTRIM$ = scratchName$

END FUNCTION ' parse_RTRIM$

''''''''''''''''''''''''
FUNCTION parse_SELECT (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "MALFORMED SELECT CASE", ASIS, 0
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> TOK_CASE THEN
    throwCompilerError "EXPECTED CASE AFTER SELECT", ASIS, 0
    EXIT FUNCTION
  END IF

  ' Generate a globally unique ID for this SELECT block
  selID = t.TiraVarCounter
  t.TiraVarCounter = t.TiraVarCounter + 1

  tira_Start

  exprVar$ = tiraParseExpression$(startIdx + 2, endIdx, 1)
  IF exprVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    hiddenName$ = "!G_SYS_SEL_SVAR_" + cTrNum$(selID) + "_DESC$"
  ELSE
    hiddenName$ = "!G_SYS_SEL_NVAR_" + cTrNum$(selID) + "_VAL"
  END IF

  ff = resolveSymbol(hiddenName$)
  IF ff = 0 THEN
    tira_Cancel
    EXIT FUNCTION
  END IF
  hiddenVarIdx = returnedData2

  symbols(hiddenVarIdx).DataType = exprIs.DataType

  ' Ensure string descriptors are cloned correctly using the runtime helper to prevent data loss
  IF exprIs.DataType = TYPE_STRING THEN
    tiraCall "RT_STR_ASSIGN", 2, hiddenName$ + ", " + exprVar$
  ELSE
    tiraAssign hiddenName$, exprVar$
  END IF

  tiraScheduleHeapReset
  tira_EndAndProcess

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_SELECT
  ctrls(ctrlCount).SelectVarIdx = hiddenVarIdx
  ctrls(ctrlCount).Patch1 = selID ' The unique SELECT block ID
  ctrls(ctrlCount).Patch2 = 0 ' Unused in TIRA
  ctrls(ctrlCount).SelectCaseSeen = 0 ' 0 means no CASE seen yet
  ctrls(ctrlCount).SelectDataType = exprIs.DataType

  ctrlCount = ctrlCount + 1

  return2 endIdx
  parse_SELECT = 1

END FUNCTION ' parse_SELECT

''''''''''''''''''''''''
FUNCTION parse_SIN$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM argFloat$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED SIN", ASIS, 0
    parse_SIN$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED SIN", ASIS, 0
    parse_SIN$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_SIN$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_SIN$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("SIN", "_VAL")
  IF scratchName$ = "" THEN
    parse_SIN$ = ""
    EXIT FUNCTION
  END IF

  ' Explicitly override the integer prefix rule to safely route as float
  ff = resolveSymbol(scratchName$)
  IF ff = 1 THEN symbols(returnedData2).DataType = TYPE_DOUBLE

  resVar$ = tiraDimVar$("T", TYPE_DOUBLE)

  ' Coerce the argument to a double for the external IAT function
  IF exprIs.DataType <> TYPE_DOUBLE THEN
    argFloat$ = tiraDimVar$("T", TYPE_DOUBLE)
    tiraAssign argFloat$, arg1$
    arg1$ = argFloat$
  END IF

  tiraCall "IAT_SIN", 1, arg1$
  tiraNew TC_GET_RET, resVar$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_DOUBLE
  exprIs.IsTemp = 1
  parse_SIN$ = scratchName$

END FUNCTION ' parse_SIN$

''''''''''''''''''''''''
FUNCTION parse_SPACE$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM skipLen$
  DIM dataPtr$
  DIM descPtr$
  DIM jmpDone$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED SPACE$", ASIS, 0
    parse_SPACE$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED SPACE$", ASIS, 0
    parse_SPACE$ = ""
    EXIT FUNCTION
  END IF

  ' Sovereign command opens its own compilation block
  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_SPACE$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "SPACE$ REQUIRES NUMERIC ARGUMENT", ASIS, 0
    parse_SPACE$ = ""
    EXIT FUNCTION
  END IF

  arg1$ = tiraForceInt$(arg1$)

  scratchName$ = tiraResolveHoistVar$("SPACE", "_DESC$")
  IF scratchName$ = "" THEN
    parse_SPACE$ = ""
    EXIT FUNCTION
  END IF

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$

  skipLen$ = tiraLabelCreateNew$("SPACE_SKIP")

  tiraJmpCond "JLE", arg1$, "0", skipLen$

  dataPtr$ = tiraAllocTempMem$(arg1$)

  ' Memset with 32 (space character)
  tiraMemSet dataPtr$, "32", arg1$

  tiraBuildStringDescriptor descPtr$, dataPtr$, arg1$, "0"

  jmpDone$ = tiraLabelCreateNew$("SPACE_DONE")
  tiraJmp jmpDone$

  tiraLabel skipLen$
  ' Safely construct an empty descriptor entirely within the Temp Heap paradigm
  tiraBuildStringDescriptor descPtr$, "0", "0", "0"
  tiraLabel jmpDone$

  ' Close the block (NO HEAP RESET, so the string survives for the parent!)
  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_SPACE$ = scratchName$

END FUNCTION ' parse_SPACE$

''''''''''''''''''''''''
FUNCTION parse_STOP (startIdx)

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  ff = verifyNoExtraTokens(endIdx, startIdx, "STOP")
  IF ff = 0 THEN EXIT FUNCTION

  tira_Start

  tiraJmp "@END_PROGRAM"

  tira_EndAndProcess

  return2 endIdx
  parse_STOP = 1

END FUNCTION ' parse_STOP

''''''''''''''''''''''''
FUNCTION parse_STR$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM basePtr$
  DIM ptr$
  DIM valVar$
  DIM isNeg$
  DIM skipNegLbl$
  DIM loopTop$
  DIM divRes$
  DIM multRes$
  DIM digit$
  DIM charVar$
  DIM skipSpaceLbl$
  DIM jmpDoneLbl$
  DIM strLen$
  DIM dataPtr$
  DIM descPtr$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED STR$", ASIS, 0
    parse_STR$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED STR$", ASIS, 0
    parse_STR$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_STR$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES NUMERIC", ASIS, 0
    parse_STR$ = ""
    EXIT FUNCTION
  END IF

  arg1$ = tiraForceInt$(arg1$)

  scratchName$ = tiraResolveHoistVar$("STR", "_DESC$")
  IF scratchName$ = "" THEN
    parse_STR$ = ""
    EXIT FUNCTION
  END IF

  basePtr$ = tiraAllocTempMem$("32")

  ptr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, ptr$, basePtr$, "32" ' start at the end of the buffer

  valVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign valVar$, arg1$

  isNeg$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign isNeg$, "0"

  skipNegLbl$ = tiraLabelCreateNew$("STR_SKIP_NEG")
  tiraJmpCond "JGE", valVar$, "0", skipNegLbl$
  tiraAssign isNeg$, "1"
  tiraOp TC_NEG, valVar$, valVar$, ""
  tiraLabel skipNegLbl$

  loopTop$ = tiraLabelCreateNew$("STR_LOOP")
  tiraLabel loopTop$

  ' digit = val MOD 10
  divRes$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_IDIV, divRes$, valVar$, "10"
  multRes$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, multRes$, divRes$, "10"
  digit$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_SUB, digit$, valVar$, multRes$

  ' char = digit + 48
  charVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, charVar$, digit$, "48"

  ' ptr = ptr - 1
  tiraOp TC_SUB, ptr$, ptr$, "1"
  tiraWriteMem ptr$, charVar$, "1"

  ' val = val / 10
  tiraAssign valVar$, divRes$
  tiraJmpCond "JG", valVar$, "0", loopTop$

  ' Apply sign or space
  tiraOp TC_SUB, ptr$, ptr$, "1"
  skipSpaceLbl$ = tiraLabelCreateNew$("STR_SKIP_SPC")
  tiraJmpCond "JE", isNeg$, "0", skipSpaceLbl$
  tiraWriteMem ptr$, "45", "1" ' -
  jmpDoneLbl$ = tiraLabelCreateNew$("STR_DONE")
  tiraJmp jmpDoneLbl$
  tiraLabel skipSpaceLbl$
  tiraWriteMem ptr$, "32", "1" ' Space
  tiraLabel jmpDoneLbl$

  ' Calculate final length
  strLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_ADD, basePtr$, basePtr$, "32"
  tiraOp TC_SUB, strLen$, basePtr$, ptr$

  dataPtr$ = ptr$

  ' Build descriptor
  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_STR$ = scratchName$

END FUNCTION ' parse_STR$

''''''''''''''''''''''''
FUNCTION parse_TIMER$ (startIdx, endIdx, allowImplicit)

  DIM scratchName$
  DIM tickVal$
  DIM tickDouble$
  DIM resVar$

  IF startIdx <> endIdx THEN
    throwCompilerError "MALFORMED TIMER", ASIS, 0
    parse_TIMER$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  scratchName$ = tiraResolveHoistVar$("TIMER", "_VAL")
  IF scratchName$ = "" THEN
    parse_TIMER$ = ""
    EXIT FUNCTION
  END IF

  ' Explicitly override the integer prefix rule to safely route as float
  ff = resolveSymbol(scratchName$)
  IF ff = 1 THEN symbols(returnedData2).DataType = TYPE_DOUBLE

  tiraCall "IAT_GETTICKCOUNT", 0, ""

  tickVal$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_GET_RET, tickVal$

  tickDouble$ = tiraDimVar$("T", TYPE_DOUBLE)
  tiraOp TC_CAST, tickDouble$, tickVal$, LTRIM$(STR$(TYPE_DOUBLE))

  resVar$ = tiraDimVar$("T", TYPE_DOUBLE)
  tiraOp TC_DIV, resVar$, tickDouble$, "1000.0"

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_DOUBLE
  exprIs.IsTemp = 1
  parse_TIMER$ = scratchName$

END FUNCTION ' parse_TIMER$

''''''''''''''''''''''''
FUNCTION parse_UCASE$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM srcPtr$
  DIM strLen$
  DIM dataPtr$
  DIM destItr$
  DIM srcItr$
  DIM itrLen$
  DIM loopTop$
  DIM loopDone$
  DIM byteVal$
  DIM skipLowerLbl$
  DIM descPtr$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED UCASE$", ASIS, 0
    parse_UCASE$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED UCASE$", ASIS, 0
    parse_UCASE$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_UCASE$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "UCASE$ REQUIRES STRING ARGUMENT", ASIS, 0
    parse_UCASE$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("UCASE", "_DESC$")
  IF scratchName$ = "" THEN
    parse_UCASE$ = ""
    EXIT FUNCTION
  END IF

  srcPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  dataPtr$ = tiraAllocTempMem$(strLen$)

  destItr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign destItr$, dataPtr$
  srcItr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign srcItr$, srcPtr$
  itrLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign itrLen$, strLen$

  loopTop$ = tiraLabelCreateNew$("UCASE_LOOP")
  loopDone$ = tiraLabelCreateNew$("UCASE_DONE")

  tiraLabel loopTop$
  tiraJmpCond "JLE", itrLen$, "0", loopDone$

  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)
  tiraNew TC_READ_MEM, byteVal$ + ", " + srcItr$

  skipLowerLbl$ = tiraLabelCreateNew$("UCASE_SKIP")
  tiraJmpCond "JL", byteVal$, "97", skipLowerLbl$
  tiraJmpCond "JG", byteVal$, "122", skipLowerLbl$
  tiraOp TC_SUB, byteVal$, byteVal$, "32"
  tiraLabel skipLowerLbl$

  tiraWriteMem destItr$, byteVal$, "1"

  tiraOp TC_ADD, srcItr$, srcItr$, "1"
  tiraOp TC_ADD, destItr$, destItr$, "1"
  tiraOp TC_SUB, itrLen$, itrLen$, "1"
  tiraJmp loopTop$

  tiraLabel loopDone$

  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign descPtr$, scratchName$
  tiraBuildStringDescriptor descPtr$, dataPtr$, strLen$, "0"

  tira_EndAndProcess

  exprIs.DataType = TYPE_STRING
  exprIs.IsTemp = 1
  parse_UCASE$ = scratchName$

END FUNCTION ' parse_UCASE$

''''''''''''''''''''''''
FUNCTION parse_VAL$ (startIdx, endIdx, allowImplicit)

  DIM arg1$
  DIM scratchName$
  DIM resVar$
  DIM dataPtr$
  DIM strLen$
  DIM isNeg$
  DIM byteVal$
  DIM skipSpaceTop$
  DIM skipSpaceDone$
  DIM checkSignDone$
  DIM numLoopTop$
  DIM numLoopDone$
  DIM applySignDone$

  IF startIdx + 3 > endIdx THEN
    throwCompilerError "MALFORMED VAL", ASIS, 0
    parse_VAL$ = ""
    EXIT FUNCTION
  END IF

  IF lineTokenVals(startIdx + 1) <> 256 + ASC("(") OR lineTokenVals(endIdx) <> 256 + ASC(")") THEN
    throwCompilerError "MALFORMED VAL", ASIS, 0
    parse_VAL$ = ""
    EXIT FUNCTION
  END IF

  tira_Start

  IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING

  arg1$ = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
  IF arg1$ = "" THEN
    tira_Cancel
    parse_VAL$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType <> TYPE_STRING THEN
    throwCompilerErrorAndCancelTira "INTRINSIC REQUIRES STRING", ASIS, 0
    parse_VAL$ = ""
    EXIT FUNCTION
  END IF

  scratchName$ = tiraResolveHoistVar$("VAL", "_VAL")
  IF scratchName$ = "" THEN
    parse_VAL$ = ""
    EXIT FUNCTION
  END IF

  resVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign resVar$, "0"

  dataPtr$ = tiraGetStringData$(arg1$)
  strLen$ = tiraGetStringLen$(arg1$)

  isNeg$ = tiraDimVar$("T", TYPE_LONG)
  tiraAssign isNeg$, "0"

  byteVal$ = tiraDimVar$("T", TYPE_UBYTE)

  skipSpaceTop$ = tiraLabelCreateNew$("VAL_SKIP_SPC")
  skipSpaceDone$ = tiraLabelCreateNew$("VAL_SPC_DONE")

  tiraLabel skipSpaceTop$
  tiraJmpCond "JLE", strLen$, "0", skipSpaceDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + dataPtr$
  tiraJmpCond "JNE", byteVal$, "32", skipSpaceDone$
  tiraOp TC_ADD, dataPtr$, dataPtr$, "1"
  tiraOp TC_SUB, strLen$, strLen$, "1"
  tiraJmp skipSpaceTop$

  tiraLabel skipSpaceDone$

  checkSignDone$ = tiraLabelCreateNew$("VAL_SGN_DONE")
  tiraJmpCond "JLE", strLen$, "0", checkSignDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + dataPtr$
  tiraJmpCond "JNE", byteVal$, "45", checkSignDone$ ' '-'
  tiraAssign isNeg$, "1"
  tiraOp TC_ADD, dataPtr$, dataPtr$, "1"
  tiraOp TC_SUB, strLen$, strLen$, "1"

  tiraLabel checkSignDone$

  numLoopTop$ = tiraLabelCreateNew$("VAL_NUM_LOOP")
  numLoopDone$ = tiraLabelCreateNew$("VAL_NUM_DONE")

  tiraLabel numLoopTop$
  tiraJmpCond "JLE", strLen$, "0", numLoopDone$
  tiraNew TC_READ_MEM, byteVal$ + ", " + dataPtr$

  tiraJmpCond "JL", byteVal$, "48", numLoopDone$ ' '0'
  tiraJmpCond "JG", byteVal$, "57", numLoopDone$ ' '9'

  tiraOp TC_SUB, byteVal$, byteVal$, "48"
  tiraOp TC_MUL, resVar$, resVar$, "10"
  tiraOp TC_ADD, resVar$, resVar$, byteVal$

  tiraOp TC_ADD, dataPtr$, dataPtr$, "1"
  tiraOp TC_SUB, strLen$, strLen$, "1"
  tiraJmp numLoopTop$

  tiraLabel numLoopDone$

  applySignDone$ = tiraLabelCreateNew$("VAL_SGN_APP")
  tiraJmpCond "JE", isNeg$, "0", applySignDone$
  tiraOp TC_NEG, resVar$, resVar$, ""
  tiraLabel applySignDone$

  tiraAssign scratchName$, resVar$

  tira_EndAndProcess

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 1
  parse_VAL$ = scratchName$

END FUNCTION ' parse_VAL$

''''''''''''''''''''''''
FUNCTION parse_WEND (startIdx)

  DIM endIdx AS LONG
  DIM loopID AS LONG

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "WEND WITHOUT WHILE", ASIS, 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_WHILE THEN
    throwCompilerError "WEND MISMATCH", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrlCount = ctrlCount - 1
  loopID = ctrls(ctrlCount).Patch1

  topLbl$ = "@WHILE_TOP_" + cTrNum$(loopID)
  doneLbl$ = "@WHILE_DONE_" + cTrNum$(loopID)

  tira_Start
  tiraScheduleHeapReset
  tiraJmp topLbl$
  tiraLabel doneLbl$
  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 endIdx
  parse_WEND = 1

END FUNCTION ' parse_WEND

''''''''''''''''''''''''
FUNCTION parse_WHILE (startIdx)

  DIM endIdx AS LONG
  DIM loopID AS LONG

  loopID = t.TiraVarCounter
  t.TiraVarCounter = t.TiraVarCounter + 1

  topLbl$ = "@WHILE_TOP_" + cTrNum$(loopID)
  doneLbl$ = "@WHILE_DONE_" + cTrNum$(loopID)

  tira_Start
  tiraLabel topLbl$
  tira_EndAndProcess

  hoistIntrinsics
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT FUNCTION

  ' Restore the expected symbol type to a clean slate
  expectedSymType = TYPE_ANY

  ff = findInstructionEnd(startIdx + 1)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2

  tira_Start

  exprVar$ = tiraParseExpressionNumeric$(startIdx + 1, endIdx, ALIM, "TYPE MISMATCH IN CONDITION")
  IF exprVar$ = "" THEN
    tira_Cancel
    EXIT FUNCTION
  END IF

  tiraJmpCond "JE", exprVar$, "0", doneLbl$

  tiraScheduleHeapReset
  tira_EndAndProcess

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_WHILE
  ctrls(ctrlCount).Patch1 = loopID
  ctrls(ctrlCount).Patch2 = 0
  ctrlCount = ctrlCount + 1

  return2 endIdx
  parse_WHILE = 1

END FUNCTION ' parse_WHILE

''''''''''''''''''''''''
FUNCTION parseAssign (startIdx)

  DIM vTokVal AS LONG
  DIM endIdx AS LONG
  DIM tokIdx AS LONG
  DIM hasIndex AS LONG
  DIM hasField AS LONG
  DIM udtOffset AS LONG
  DIM closeParenIdx AS LONG
  DIM hasComma AS LONG
  DIM commaIdx AS LONG
  DIM eqIdx AS LONG
  DIM vIdx AS LONG
  DIM targetType AS LONG
  DIM uIdx AS LONG
  DIM fieldFound AS LONG
  DIM iField AS LONG
  DIM lhsUdtIndex AS LONG
  DIM fieldCnt AS LONG
  DIM fieldOffset AS LONG
  DIM fieldSize AS LONG
  DIM fType AS LONG
  DIM isFixedStr AS LONG
  DIM destLen AS LONG
  DIM tempUdtIndex AS LONG
  DIM tempIsDynamicString AS LONG
  DIM tempFieldSize AS LONG

  vTok$ = lineTokens$(startIdx)
  vTokVal = lineTokenVals(startIdx)

  IF vTokVal = 0 AND LEN(vTok$) > 0 THEN
    vName$ = UCASE$(vTok$)

    ff = findInstructionEnd(startIdx + 1)
    IF ff = 0 THEN EXIT FUNCTION
    endIdx = returnedData2

    tokIdx = startIdx + 1

    ' Identify and validate array index boundaries
    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
        hasIndex = 1
        IF findMatchingParen(tokIdx, endIdx) = 1 THEN ' Close parenthesis found
          closeParenIdx = returnedData2
        ELSE
          EXIT FUNCTION
        END IF

        commaIdx = findComma(tokIdx + 1, closeParenIdx - 1)
        IF commaIdx > 0 THEN
          hasComma = 1
        END IF ' hasComma and commaIdx remain zero otherwise

        tokIdx = closeParenIdx + 1
      END IF
    END IF

    ' Detect and process UDT field separator
    IF tokIdx <= endIdx THEN
      IF lineTokenVals(tokIdx) = 256 + ASC(".") THEN
        hasField = 1
        tokIdx = tokIdx + 2 ' Skip the dot and the field name
      END IF
    END IF

    ' Verify the presence of assignment operator
    IF tokIdx > endIdx OR lineTokenVals(tokIdx) <> 256 + ASC("=") THEN EXIT FUNCTION
    eqIdx = tokIdx

    ' RHS Lookahead for Duck Typing of LHS variable
    ff = checkExpressionForString(eqIdx + 1, endIdx)

    IF ff = 1 THEN
      expectedSymType = TYPE_STRING
    ELSE
      expectedSymType = TYPE_SINGLE
    END IF

    ff = resolveSymbol(vName$)
    IF ff = 0 THEN EXIT FUNCTION
    vIdx = returnedData2
    targetType = returnedData3

    ' Extract and process UDT field metadata
    IF hasField = 1 THEN
      fNameTok$ = UCASE$(lineTokens$(eqIdx - 1))
      IF targetType <> TYPE_UDT THEN
        throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
        EXIT FUNCTION
      END IF

      uIdx = symbols(vIdx).UDTIndex
      fieldFound = 0
      tempUdtIndex = 0
      tempIsDynamicString = 0
      FOR iField = 0 TO udts(uIdx).FieldCount - 1
        IF RTRIM$(udtFields(uIdx, iField).FieldName) = fNameTok$ THEN
          udtOffset = udtFields(uIdx, iField).Offset
          targetType = udtFields(uIdx, iField).DataType
          tempUdtIndex = udtFields(uIdx, iField).UDTIndex
          tempFieldSize = udtFields(uIdx, iField).Size
          tempIsDynamicString = udtFields(uIdx, iField).IsDynamicString
          fieldFound = 1
          EXIT FOR
        END IF
      NEXT

      IF fieldFound = 0 THEN
        throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF

    ' Validate array dimensions against declaration status
    IF hasIndex = 1 THEN
      IF symbols(vIdx).IsArray = 0 THEN
        throwCompilerError "ARRAY NOT DIMMED", ASIS, 0
        EXIT FUNCTION
      END IF
      IF hasComma = 1 AND symbols(vIdx).Size2 = 0 AND symbols(vIdx).IsArray <> 2 THEN
        throwCompilerError "EXPECTED 2D ARRAY", ASIS, 0
        EXIT FUNCTION
      END IF
      IF hasComma = 0 AND symbols(vIdx).Size2 > 0 AND symbols(vIdx).IsArray <> 2 THEN
        throwCompilerError "EXPECTED 2D ARRAY", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF

    tira_Start

    ' Parse the left side array indices
    xVar$ = ""
    yVar$ = ""
    IF hasIndex = 1 THEN
      IF hasComma = 0 THEN
        xVar$ = tiraParseExpressionInt$(startIdx + 2, closeParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
        IF xVar$ = "" THEN
          tira_Cancel
          EXIT FUNCTION
        END IF
      ELSE
        xVar$ = tiraParseExpressionInt$(startIdx + 2, commaIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
        IF xVar$ = "" THEN
          tira_Cancel
          EXIT FUNCTION
        END IF

        yVar$ = tiraParseExpressionInt$(commaIdx + 1, closeParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
        IF yVar$ = "" THEN
          tira_Cancel
          EXIT FUNCTION
        END IF
      END IF
    END IF

    IF targetType = TYPE_UDT THEN
      lhsUdtIndex = symbols(vIdx).UDTIndex
      IF hasField = 1 THEN lhsUdtIndex = tempUdtIndex

      ' Call the isolated helper function to evaluate and validate the right side UDT
      rhsBase$ = tiraParseRhsUdtBase$(eqIdx + 1, endIdx, lhsUdtIndex)
      IF rhsBase$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      ' Calculate the source and destination memory addresses
      lhsBase$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), xVar$, yVar$, udtOffset)
      IF lhsBase$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      ' Perform deep cloning of UDT field data
      fieldCnt = udts(lhsUdtIndex).FieldCount
      FOR iField = 0 TO fieldCnt - 1
        fieldOffset = udtFields(lhsUdtIndex, iField).Offset
        fieldSize = udtFields(lhsUdtIndex, iField).Size
        fType = udtFields(lhsUdtIndex, iField).DataType

        IF fType = TYPE_STRING AND udtFields(lhsUdtIndex, iField).IsDynamicString = 1 THEN
          rhsDescAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, rhsDescAddr$, rhsBase$, LTRIM$(STR$(fieldOffset))

          rhsDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraNew TC_READ_MEM, rhsDescPtr$ + ", " + rhsDescAddr$

          skipRhsNull$ = tiraLabelCreateNew$("SKIP_RHS_NULL")
          tiraJmpCond "JNE", rhsDescPtr$, "0", skipRhsNull$
          tiraAssign rhsDescPtr$, "!G_SYS_EMPTY_DESC$"
          tiraLabel skipRhsNull$

          lhsDescAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, lhsDescAddr$, lhsBase$, LTRIM$(STR$(fieldOffset))

          lhsDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraNew TC_READ_MEM, lhsDescPtr$ + ", " + lhsDescAddr$

          tiraEnsureStringAlloc lhsDescPtr$, lhsDescAddr$

          tiraCall "RT_STR_ASSIGN", 2, lhsDescPtr$ + ", " + rhsDescPtr$
        ELSE
          lhsFieldAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, lhsFieldAddr$, lhsBase$, LTRIM$(STR$(fieldOffset))

          rhsFieldAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, rhsFieldAddr$, rhsBase$, LTRIM$(STR$(fieldOffset))

          tiraMemcpy lhsFieldAddr$, rhsFieldAddr$, LTRIM$(STR$(fieldSize))
        END IF
      NEXT iField
    ELSE
      ' Parse the right side scalar or string expression
      rhsVar$ = tiraParseExpression$(eqIdx + 1, endIdx, 0)
      IF rhsVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF
      IF targetType = TYPE_STRING AND exprIs.DataType <> TYPE_STRING THEN
        throwCompilerErrorAndCancelTira "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF
      IF targetType <> TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        throwCompilerErrorAndCancelTira "TYPE MISMATCH", ASIS, 0
        EXIT FUNCTION
      END IF

      IF targetType = TYPE_STRING THEN
        isFixedStr = 0
        destLen = 0
        IF hasField = 1 THEN
          IF tempIsDynamicString = 0 THEN
            isFixedStr = 1
            destLen = tempFieldSize
          END IF
        ELSE
          destLen = retFixedStringLength(vIdx)
          IF destLen > 0 THEN
            isFixedStr = 1
          END IF
        END IF

        IF isFixedStr = 1 THEN
          lhsDataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
          IF xVar$ = "" AND yVar$ = "" AND udtOffset = 0 THEN
            lhsDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
            tiraAssign lhsDescPtr$, RTRIM$(symbols(vIdx).RecordName)
            tiraNew TC_READ_MEM, lhsDataPtr$ + ", " + lhsDescPtr$
          ELSE
            finalAddr$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), xVar$, yVar$, udtOffset)
            IF finalAddr$ = "" THEN
              tira_Cancel
              EXIT FUNCTION
            END IF
            tiraAssign lhsDataPtr$, finalAddr$
          END IF

          rhsDataPtr$ = tiraGetStringData$(rhsVar$)
          rhsLen$ = tiraGetStringLen$(rhsVar$)

          minLen$ = tiraDimVar$("T", TYPE_LONG)
          tiraAssign minLen$, rhsLen$
          tiraClamp minLen$, "", LTRIM$(STR$(destLen))

          tiraMemcpy lhsDataPtr$, rhsDataPtr$, minLen$

          padLen$ = tiraDimVar$("T", TYPE_LONG)
          tiraOp TC_SUB, padLen$, LTRIM$(STR$(destLen)), minLen$
          skipPadLbl$ = tiraLabelCreateNew$("SKIP_PAD")
          tiraJmpCond "JLE", padLen$, "0", skipPadLbl$

          padAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, padAddr$, lhsDataPtr$, minLen$
          tiraMemSet padAddr$, "32", padLen$

          tiraLabel skipPadLbl$
        ELSE
          lhsDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
          IF xVar$ = "" AND yVar$ = "" AND udtOffset = 0 THEN
            tiraAssign lhsDescPtr$, RTRIM$(symbols(vIdx).RecordName)
          ELSE
            finalAddr$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), xVar$, yVar$, udtOffset)
            IF finalAddr$ = "" THEN
              tira_Cancel
              EXIT FUNCTION
            END IF
            tiraNew TC_READ_MEM, lhsDescPtr$ + ", " + finalAddr$

            tiraEnsureStringAlloc lhsDescPtr$, finalAddr$
          END IF

          tiraCall "RT_STR_ASSIGN", 2, lhsDescPtr$ + ", " + rhsVar$
        END IF

      ELSE
        ' Scalar write
        IF hasIndex = 0 AND hasField = 0 THEN
          tiraAssign RTRIM$(symbols(vIdx).RecordName), rhsVar$
        ELSE
          destAddr$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), xVar$, yVar$, udtOffset)
          IF destAddr$ = "" THEN
            tira_Cancel
            EXIT FUNCTION
          END IF

          sMode$ = "8"

          SELECT CASE targetType

            CASE TYPE_BYTE, TYPE_UBYTE: sMode$ = "1"
            CASE TYPE_INTEGER, TYPE_UINTEGER: sMode$ = "2"
            CASE TYPE_LONG, TYPE_ULONG: sMode$ = "4"
            CASE TYPE_INTEGER64, TYPE_UINT64: sMode$ = "8"
            CASE TYPE_SINGLE: sMode$ = "SINGLE"
            CASE TYPE_DOUBLE: sMode$ = "DOUBLE"

          END SELECT ' targetType

          tiraWriteMem destAddr$, rhsVar$, sMode$
        END IF
      END IF
    END IF

    tiraScheduleHeapReset
    tira_EndAndProcess

    return2 endIdx
    parseAssign = 1
    EXIT FUNCTION
  END IF

END FUNCTION ' parseAssign

''''''''''''''''''''''''
FUNCTION parseAssignRouter (startIdx)

  ' If the line starts with an identifier (variables, arrays, function names, labels)
  ' this function acts as a probe. It scans forward, cleanly skipping over array indices
  '  (1, 2) and UDT fields .X, looking for an = sign. If it finds one, it
  '  confidently hands the line over to parseAssign. If it doesn't, it returns IMPLICIT_NOT_ASSIGN
  '  to tell parseStatement to try evaluating it as a subroutine call instead.

  DIM tempSuccess AS LONG
  DIM checkIdx AS LONG
  DIM pDepth AS LONG
  DIM tVal AS LONG
  DIM assignRes AS LONG

  tempSuccess = IMPLICIT_NOT_ASSIGN
  checkIdx = startIdx + 1

  ' Fast-fail lookahead: Skip over any array parentheses
  IF checkIdx < lineTokenCount THEN
    IF lineTokenVals(checkIdx) = 256 + ASC("(") THEN
      pDepth = 0
      FOR ii = checkIdx TO lineTokenCount - 1
        tVal = lineTokenVals(ii)
        IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
        IF tVal = 256 + ASC(")") THEN
          pDepth = pDepth - 1
          IF pDepth = 0 THEN
            checkIdx = ii + 1
            EXIT FOR
          END IF
        END IF
      NEXT
    END IF
  END IF

  ' Fast-fail lookahead: Skip over any UDT fields
  IF checkIdx < lineTokenCount THEN
    IF lineTokenVals(checkIdx) = 256 + ASC(".") THEN
      checkIdx = checkIdx + 2 ' Skip the dot and the field name
    END IF
  END IF

  ' Check if the resulting token is an equals sign
  IF checkIdx < lineTokenCount THEN
    IF lineTokenVals(checkIdx) = 256 + ASC("=") THEN
      ' We found an equals sign, and thus this is definitively an assignment
      assignRes = parseAssign(startIdx)

      IF assignRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = IMPLICIT_FAIL
        IF compileStatusMsg$ = "" THEN throwCompilerError "ASSIGN", WITHFAILED, 0
      ELSE
        tempSuccess = IMPLICIT_SUCCESS
      END IF
      parseAssignRouter = tempSuccess
      EXIT FUNCTION
    END IF
  END IF

  ' No equals sign found. Return IMPLICIT_NOT_ASSIGN so the parser can try treating it as a SUB call.
  parseAssignRouter = tempSuccess

END FUNCTION ' parseAssignRouter

''''''''''''''''''''''''
FUNCTION parseIntrinsic$ (startIdx, endIdx, allowImplicit)

  DIM tVal AS LONG
  tVal = lineTokenVals(startIdx)

  SELECT CASE tVal

    CASE TOK_HEX
      parseIntrinsic$ = parse_HEX$(startIdx, endIdx, allowImplicit)

    CASE TOK_SPACE
      parseIntrinsic$ = parse_SPACE$(startIdx, endIdx, allowImplicit)

    CASE TOK_CHR
      parseIntrinsic$ = parse_CHR$(startIdx, endIdx, allowImplicit)

    CASE TOK_LEN
      parseIntrinsic$ = parse_LEN$(startIdx, endIdx, allowImplicit)

    CASE TOK_ASC
      parseIntrinsic$ = parse_ASC$(startIdx, endIdx, allowImplicit)

    CASE TOK_LTRIM
      parseIntrinsic$ = parse_LTRIM$(startIdx, endIdx, allowImplicit)

    CASE TOK_RTRIM
      parseIntrinsic$ = parse_RTRIM$(startIdx, endIdx, allowImplicit)

    CASE TOK_UCASE
      parseIntrinsic$ = parse_UCASE$(startIdx, endIdx, allowImplicit)

    CASE TOK_LEFT
      parseIntrinsic$ = parse_LEFT$(startIdx, endIdx, allowImplicit)

    CASE TOK_RIGHT
      parseIntrinsic$ = parse_RIGHT$(startIdx, endIdx, allowImplicit)

    CASE TOK_STR
      parseIntrinsic$ = parse_STR$(startIdx, endIdx, allowImplicit)

    CASE TOK_VAL
      parseIntrinsic$ = parse_VAL$(startIdx, endIdx, allowImplicit)

    CASE TOK_MID
      parseIntrinsic$ = parse_MID$(startIdx, endIdx, allowImplicit)

    CASE TOK_INT
      parseIntrinsic$ = parse_INT$(startIdx, endIdx, allowImplicit)

    CASE TOK_ATN
      parseIntrinsic$ = parse_ATN$(startIdx, endIdx, allowImplicit)

    CASE TOK_KEYDOWN
      parseIntrinsic$ = parse_KEYDOWN$(startIdx, endIdx, allowImplicit)

    CASE TOK_INKEY
      parseIntrinsic$ = parse_INKEY$(startIdx, endIdx, allowImplicit)

    CASE TOK_INKEYF
      parseIntrinsic$ = parse_INKEYF$(startIdx, endIdx, allowImplicit)

    CASE TOK_LOF
      parseIntrinsic$ = parse_LOF$(startIdx, endIdx, allowImplicit)

    CASE TOK_POINT
      parseIntrinsic$ = parse_POINT$(startIdx, endIdx, allowImplicit)

    CASE TOK_RGB32
      parseIntrinsic$ = parse_RGB32$(startIdx, endIdx, allowImplicit)

    CASE TOK_PEEK
      parseIntrinsic$ = parse_PEEK$(startIdx, endIdx, allowImplicit)

    CASE TOK_SIN
      parseIntrinsic$ = parse_SIN$(startIdx, endIdx, allowImplicit)

    CASE TOK_COS
      parseIntrinsic$ = parse_COS$(startIdx, endIdx, allowImplicit)

    CASE TOK_TIMER
      parseIntrinsic$ = parse_TIMER$(startIdx, endIdx, allowImplicit)

    CASE TOK_MOUSEINPUT
      parseIntrinsic$ = parse_MOUSEINPUT$(startIdx, endIdx, allowImplicit)

    CASE TOK_MOUSEX
      parseIntrinsic$ = parse_MOUSEX$(startIdx, endIdx, allowImplicit)

    CASE TOK_MOUSEY
      parseIntrinsic$ = parse_MOUSEY$(startIdx, endIdx, allowImplicit)

    CASE TOK_MOUSEBUTTON
      parseIntrinsic$ = parse_MOUSEBUTTON$(startIdx, endIdx, allowImplicit)

    CASE TOK_MOUSEWHEEL
      parseIntrinsic$ = parse_MOUSEWHEEL$(startIdx, endIdx, allowImplicit)

    CASE ELSE
      throwCompilerError "UNIMPLEMENTED HOISTED INTRINSIC", ASIS, 0
      parseIntrinsic$ = ""

  END SELECT

END FUNCTION ' parseIntrinsic$

''''''''''''''''''''''''
FUNCTION parseStatement (startIdx)

  DIM tempSuccess AS LONG
  DIM fullscreenRes AS LONG
  DIM tVal AS LONG
  DIM endIdx AS LONG
  DIM tokIdx AS LONG
  DIM beepRes AS LONG
  DIM callRes AS LONG
  DIM caseRes AS LONG
  DIM clsRes AS LONG
  DIM colorRes AS LONG
  DIM isDefFnSpace AS LONG
  DIM nameIdx AS LONG
  DIM subIdx AS LONG
  DIM hasEq AS LONG
  DIM eqIdx AS LONG
  DIM retVarIdx AS LONG
  DIM targetType AS LONG
  DIM dimRes AS LONG
  DIM doRes AS LONG
  DIM endRes AS LONG
  DIM exitRes AS LONG
  DIM forRes AS LONG
  DIM globalRes AS LONG
  DIM gosubRes AS LONG
  DIM gotoRes AS LONG
  DIM ifRes AS LONG
  DIM inputRes AS LONG
  DIM assignRes AS LONG
  DIM lineRes AS LONG
  DIM locateRes AS LONG
  DIM loopRes AS LONG
  DIM nextRes AS LONG
  DIM onRes AS LONG
  DIM printRes AS LONG
  DIM psetRes AS LONG
  DIM resumeRes AS LONG
  DIM returnRes AS LONG
  DIM selectRes AS LONG
  DIM getRes AS LONG
  DIM putRes AS LONG
  DIM displayRes AS LONG
  DIM displayiRes AS LONG
  DIM openRes AS LONG
  DIM closeRes AS LONG
  DIM killRes AS LONG
  DIM paletteColorRes AS LONG
  DIM stopRes AS LONG
  DIM vIdx AS LONG
  DIM isUnrecognized AS LONG
  DIM matchPosErr AS LONG
  DIM chunkStartErr AS LONG
  DIM chunkEndErr AS LONG
  DIM chPrevErr AS STRING * 1
  DIM chNextErr AS STRING * 1
  DIM inQuotesErr AS LONG
  DIM iScan AS LONG
  DIM chScan AS STRING * 1
  DIM whileRes AS LONG

  tempSuccess = 1

  expectedSymType = TYPE_ANY

  firstTok$ = lineTokens$(startIdx)
  tVal = lineTokenVals(startIdx)
  isUnrecognized = 0

  ' Handle loop structures that need their labels emitted BEFORE intrinsic hoisting
  IF tVal = TOK_DO THEN
    doRes = parse_DO(startIdx)
    IF doRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      tempSuccess = 0
      IF compileStatusMsg$ = "" THEN throwCompilerError "DO", WITHFAILED, 0
    END IF
    parseStatement = tempSuccess
    EXIT FUNCTION
  END IF

  IF tVal = TOK_WHILE THEN
    whileRes = parse_WHILE(startIdx)
    IF whileRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      tempSuccess = 0
      IF compileStatusMsg$ = "" THEN throwCompilerError "WHILE", WITHFAILED, 0
    END IF
    parseStatement = tempSuccess
    EXIT FUNCTION
  END IF

  ' For all other statements, hoist intrinsics before parsing!
  hoistIntrinsics
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    parseStatement = 0
    EXIT FUNCTION
  END IF

  ' Restore the expected symbol type to a clean slate, as intrinsic evaluations
  ' may have leaked their duck-typing lookahead values into the global scope
  expectedSymType = TYPE_ANY

  ' Re-read first token in case it was an intrinsic that got hoisted!
  firstTok$ = lineTokens$(startIdx)
  tVal = lineTokenVals(startIdx)

  SELECT CASE tVal

    CASE TOK_CLASSIC, TOK_STRINGSTRICT

    CASE TOK_DEFINT, TOK_DEFINT_NORM
      ff = findInstructionEnd(startIdx + 1)
      IF ff = 0 THEN EXIT FUNCTION

    CASE TOK_GDOUBLE

    CASE TOK_GRAPHICS
      tokIdx = startIdx + 1

      IF tokIdx < lineTokenCount THEN
        gTok$ = lineTokens$(tokIdx)
        IF LEFT$(gTok$, 1) >= "0" AND LEFT$(gTok$, 1) <= "9" THEN
          gfxConfig.SizeX = VAL(gTok$)
          IF gfxConfig.SizeX < 64 OR gfxConfig.SizeX > FRAMEBUF_MAX_WIDTH THEN
            throwCompilerError "X MUST BE 64 TO 1024", ASIS, 0
            EXIT FUNCTION
          END IF
          tokIdx = tokIdx + 1

          IF tokIdx < lineTokenCount THEN
            IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
              tokIdx = tokIdx + 1
            ELSE
              throwCompilerError "EXPECTED COMMA AFTER X", ASIS, 0
              EXIT FUNCTION
            END IF
          ELSE
            throwCompilerError "EXPECTED Y RESOLUTION", ASIS, 0
            EXIT FUNCTION
          END IF

          IF tokIdx < lineTokenCount THEN
            gTok$ = lineTokens$(tokIdx)
            IF LEFT$(gTok$, 1) >= "0" AND LEFT$(gTok$, 1) <= "9" THEN
              gfxConfig.SizeY = VAL(gTok$)
              IF gfxConfig.SizeY < 64 OR gfxConfig.SizeY > FRAMEBUF_MAX_HEIGHT THEN
                throwCompilerError "Y MUST BE 64 TO 1080", ASIS, 0
                EXIT FUNCTION
              END IF
              tokIdx = tokIdx + 1
            ELSE
              throwCompilerError "EXPECTED Y RESOLUTION", ASIS, 0
              EXIT FUNCTION
            END IF
          ELSE
            throwCompilerError "EXPECTED Y RESOLUTION", ASIS, 0
            EXIT FUNCTION
          END IF

          IF tokIdx < lineTokenCount THEN
            IF lineTokenVals(tokIdx) = 256 + ASC(",") THEN
              tokIdx = tokIdx + 1
            END IF
          END IF
        END IF
      END IF

      IF tokIdx < lineTokenCount THEN
        gTok$ = lineTokens$(tokIdx)
        IF LEFT$(gTok$, 1) = CHR$(34) THEN
          compileWindowTitle$ = extractQuotes$(gTok$)
          tokIdx = tokIdx + 1
        ELSE
          throwCompilerError "EXPECTED WINDOW NAME", ASIS, 0
          EXIT FUNCTION
        END IF
      END IF

      ff = verifyNoExtraTokens(lineTokenCount - 1, tokIdx - 1, "GRAPHICS")
      IF ff = 0 THEN
        EXIT FUNCTION
      END IF

    CASE TOK_BEEP
      beepRes = parse_BEEP(startIdx)
      IF beepRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "BEEP", WITHFAILED, 0
      END IF

    CASE TOK_CALL
      subName$ = UCASE$(lineTokens$(startIdx + 1))
      ff = findSymbol(subName$)
      IF ff = 1 THEN
        vIdx = returnedData2
      ELSE
        vIdx = -1
      END IF
      callRes = parseSubCall(startIdx, 1, vIdx)
      IF callRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CALL", WITHFAILED, 0
      END IF

    CASE TOK_CASE
      caseRes = parse_CASE(startIdx)
      IF caseRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CASE", WITHFAILED, 0
      END IF

    CASE TOK_CLOSE
      closeRes = parse_CLOSE(startIdx)
      IF closeRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CLOSE", WITHFAILED, 0
      END IF

    CASE TOK_CLS
      clsRes = parse_CLS(startIdx)
      IF clsRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CLS", WITHFAILED, 0
      END IF

    CASE TOK_COLOR
      colorRes = parse_COLOR(startIdx)
      IF colorRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "COLOR", WITHFAILED, 0
      END IF

    CASE TOK_COMMON
      commonRes = parse_COMMON(startIdx)
      IF commonRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "COMMON", WITHFAILED, 0
      END IF

    CASE TOK_DEF
      ff = findInstructionEnd(startIdx + 1)
      IF ff = 0 THEN EXIT FUNCTION
      endIdx = returnedData2

      IF endIdx >= startIdx + 1 THEN
        IF UCASE$(lineTokens$(startIdx + 1)) = "SEG" THEN

        ELSE
          IF endIdx < startIdx + 2 THEN
            throwCompilerError "MALFORMED DEF", ASIS, 0
            tempSuccess = 0
          ELSE
            defNameTok$ = lineTokens$(startIdx + 1)
            isDefFnSpace = 0
            IF UCASE$(defNameTok$) = "FN" THEN isDefFnSpace = 1

            IF isDefFnSpace = 0 AND LEFT$(defNameTok$, 2) <> "Fn" THEN
              throwCompilerError "DEF MUST BE FOLLOWED BY FN OR Fn*()", ASIS, 0
              tempSuccess = 0
            ELSE
              nameIdx = startIdx + 1
              subName$ = UCASE$(defNameTok$)

              IF isDefFnSpace = 1 THEN
                IF endIdx >= startIdx + 2 THEN
                  nameIdx = startIdx + 2
                  subName$ = "FN" + UCASE$(lineTokens$(startIdx + 2))
                ELSE
                  throwCompilerError "MALFORMED DEF", ASIS, 0
                  tempSuccess = 0
                END IF
              END IF

              IF tempSuccess = 1 THEN
                ff = findSubIndex(subName$)
                IF ff = 0 THEN
                  throwCompilerError "DEF NOT FOUND", ASIS, 0
                  tempSuccess = 0
                ELSE
                  subIdx = returnedData2
                  currentScopeID = subs(subIdx).ScopeID
                  insideSub = 2
                  currentSubName$ = subName$

                  hasEq = 0
                  eqIdx = 0
                  FOR ii = nameIdx + 1 TO endIdx
                    IF lineTokenVals(ii) = 256 + ASC("=") THEN
                      hasEq = 1
                      eqIdx = ii
                      EXIT FOR
                    END IF
                  NEXT

                  IF hasEq = 0 THEN
                    throwCompilerError "DEF MISSING =", ASIS, 0
                    tempSuccess = 0
                  ELSE
                    tira_Start
                    tiraJmp "@SKIP_ROUTINE_" + subName$
                    tiraSetSubOffset subIdx
                    tiraScheduleSubPrologue

                    exprVar$ = tiraParseExpression$(eqIdx + 1, endIdx, 0)
                    IF exprVar$ = "" THEN
                      tira_Cancel
                      tempSuccess = 0
                    ELSE
                      retVarIdx = subs(subIdx).ReturnVarIdx
                      targetType = symbols(retVarIdx).DataType

                      IF targetType = TYPE_STRING THEN
                        throwCompilerErrorAndCancelTira "DEF FN CANNOT RETURN STRING", ASIS, 0
                        tempSuccess = 0
                      ELSE
                        targetVarName$ = "#" + LTRIM$(STR$(retVarIdx))
                        tiraAssign targetVarName$, exprVar$

                        tiraScheduleGC
                        tiraScheduleSubEpilogue
                        tiraLabel "@SKIP_ROUTINE_" + subName$
                        tira_EndAndProcess

                        currentScopeID = 0
                        insideSub = 0
                        currentSubName$ = ""
                      END IF
                    END IF
                  END IF
                END IF
              END IF
            END IF
          END IF
        END IF
      ELSE
        throwCompilerError "MALFORMED DEF", ASIS, 0
        tempSuccess = 0
      END IF

    CASE TOK_DIM
      dimRes = parse_DIM(startIdx)
      IF dimRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "DIM", WITHFAILED, 0
      END IF

    CASE TOK_DISPLAY
      displayRes = parse_DISPLAY(startIdx)
      IF displayRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "_DISPLAY", WITHFAILED, 0
      END IF

    CASE TOK_DISPLAYI
      displayiRes = parse_DISPLAYI(startIdx)
      IF displayiRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "_DISPLAYI", WITHFAILED, 0
      END IF

    CASE TOK_DO
      ' Handled above to prevent structural breakage

    CASE TOK_ELSE
      ff = findInstructionEnd(startIdx + 1)
      IF ff = 0 THEN EXIT FUNCTION

      IF ctrlCount = 0 THEN
        throwCompilerError "ELSE WITHOUT IF", ASIS, 0
        EXIT FUNCTION
      END IF
      IF ctrls(ctrlCount - 1).Type <> CTRL_IF THEN
        throwCompilerError "ELSE WITHOUT IF", ASIS, 0
        EXIT FUNCTION
      END IF

      ifID = ctrls(ctrlCount - 1).Patch1
      falseLbl$ = "@IF_FALSE_" + cTrNum$(ifID)
      endLbl$ = "@IF_END_" + cTrNum$(ifID)

      tira_Start
      tiraScheduleHeapReset
      tiraJmp endLbl$
      tiraLabel falseLbl$
      tiraScheduleHeapReset
      tira_EndAndProcess

      ctrls(ctrlCount - 1).Type = CTRL_ELSE

    CASE TOK_END
      endRes = parse_END(startIdx)
      IF endRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "END", WITHFAILED, 0
      END IF

    CASE TOK_EXIT
      exitRes = parse_EXIT(startIdx)
      IF exitRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "EXIT", WITHFAILED, 0
      END IF

    CASE TOK_FOR
      forRes = parse_FOR(startIdx)
      IF forRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "FOR", WITHFAILED, 0
      END IF

    CASE TOK_FULLSCREEN
      fullscreenRes = parse_FULLSCREEN(startIdx)
      IF fullscreenRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "_FULLSCREEN", WITHFAILED, 0
      END IF

    CASE TOK_FUNCTION
      IF lineTokenCount < startIdx + 2 THEN
        throwCompilerError "MALFORMED FUNCTION", ASIS, 0
        tempSuccess = 0
      ELSE
        subName$ = UCASE$(lineTokens$(startIdx + 1))
        ff = findSubIndex(subName$)
        IF ff = 0 THEN
          throwCompilerError "FUNCTION NOT FOUND", ASIS, 0
          tempSuccess = 0
        ELSE
          subIdx = returnedData2
          currentScopeID = subs(subIdx).ScopeID
          insideSub = 2
          currentSubName$ = subName$

          tira_Start
          tiraJmp "@SKIP_ROUTINE_" + subName$
          tiraSetSubOffset subIdx
          tiraScheduleSubPrologue
          tira_EndAndProcess
        END IF
      END IF

    CASE TOK_GET
      getRes = parse_GET(startIdx)
      IF getRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "GET", WITHFAILED, 0
      END IF

    CASE TOK_GLOBAL
      globalRes = parse_GLOBAL(startIdx)
      IF globalRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "GLOBAL", WITHFAILED, 0
      END IF

    CASE TOK_GOSUB
      gosubRes = parse_GOSUB(startIdx)
      IF gosubRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "GOSUB", WITHFAILED, 0
      END IF

    CASE TOK_GOTO
      gotoRes = parse_GOTO(startIdx)
      IF gotoRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "GOTO", WITHFAILED, 0
      END IF

    CASE TOK_IF
      ifRes = parse_IF(startIdx)
      IF ifRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "IF", WITHFAILED, 0
      END IF

    CASE TOK_INPUT
      inputRes = parse_INPUT(startIdx)
      IF inputRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "INPUT", WITHFAILED, 0
      END IF

    CASE TOK_KILL
      killRes = parse_KILL(startIdx)
      IF killRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "KILL", WITHFAILED, 0
      END IF

    CASE TOK_LET
      assignRes = parseAssign(startIdx + 1)
      IF assignRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "ASSIGN", WITHFAILED, 0
      END IF

    CASE TOK_LINE
      IF compileHasGraphics = 0 THEN
        throwCompilerError "LINE REQUIRES #GRAPHICS", ASIS, 0
        EXIT FUNCTION
      END IF
      lineRes = parse_LINE(startIdx)
      IF lineRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "LINE", WITHFAILED, 0
      END IF

    CASE TOK_LOCATE
      locateRes = parse_LOCATE(startIdx)
      IF locateRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "LOCATE", WITHFAILED, 0
      END IF

    CASE TOK_LOOP
      loopRes = parse_LOOP(startIdx)
      IF loopRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "LOOP", WITHFAILED, 0
      END IF

    CASE TOK_NEXT
      nextRes = parse_NEXT(startIdx)
      IF nextRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "NEXT", WITHFAILED, 0
      END IF

    CASE TOK_ON
      onRes = parse_ON(startIdx)
      IF onRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "ON", WITHFAILED, 0
      END IF

    CASE TOK_OPEN
      openRes = parse_OPEN(startIdx)
      IF openRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "OPEN", WITHFAILED, 0
      END IF

    CASE TOK_PALETTECOLOR
      paletteColorRes = parse_PALETTECOLOR(startIdx)
      IF paletteColorRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "_PALETTECOLOR", WITHFAILED, 0
      END IF

    CASE TOK_POKE
      ff = findInstructionEnd(startIdx + 1)
      IF ff = 0 THEN EXIT FUNCTION

    CASE TOK_PRINT
      printRes = parse_PRINT(startIdx)
      IF printRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "PRINT", WITHFAILED, 0
      END IF

    CASE TOK_PSET
      IF compileHasGraphics = 0 THEN
        throwCompilerError "PSET REQUIRES #GRAPHICS", ASIS, 0
        EXIT FUNCTION
      END IF
      psetRes = parse_PSET(startIdx)
      IF psetRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "PSET", WITHFAILED, 0
      END IF

    CASE TOK_PUT
      putRes = parse_PUT(startIdx)
      IF putRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "PUT", WITHFAILED, 0
      END IF

    CASE TOK_RESUME
      resumeRes = parse_RESUME(startIdx)
      IF resumeRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "RESUME", WITHFAILED, 0
      END IF

    CASE TOK_RETURN
      returnRes = parse_RETURN(startIdx)
      IF returnRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "RETURN", WITHFAILED, 0
      END IF

    CASE TOK_SCREEN, TOK_FONT, TOK_LIMIT

    CASE TOK_SELECT
      selectRes = parse_SELECT(startIdx)
      IF selectRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "SELECT", WITHFAILED, 0
      END IF

    CASE TOK_STOP
      stopRes = parse_STOP(startIdx)
      IF stopRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "STOP", WITHFAILED, 0
      END IF

    CASE TOK_STRING
      ff = findInstructionEnd(startIdx + 1)
      IF ff = 0 THEN EXIT FUNCTION
      endIdx = returnedData2

      IF endIdx < startIdx + 1 THEN
        throwCompilerError "EXPECTED IDENTIFIER", ASIS, 0
        tempSuccess = 0
      ELSE
        vTok$ = lineTokens$(startIdx + 1)
        IF lineTokenVals(startIdx + 1) <> 0 THEN
          throwCompilerError "EXPECTED IDENTIFIER", ASIS, 0
          tempSuccess = 0
        ELSE
          vName$ = UCASE$(vTok$)

          ff = resolveSymbol(vName$)
          IF ff = 0 THEN
            tempSuccess = 0
          ELSE
            vIdx = returnedData2

            IF endIdx >= startIdx + 2 THEN
              IF lineTokenVals(startIdx + 2) = 256 + ASC("=") THEN
                assignRes = parseAssign(startIdx + 1)
                IF assignRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                  tempSuccess = 0
                  IF compileStatusMsg$ = "" THEN throwCompilerError "ASSIGN", WITHFAILED, 0
                END IF
              ELSE
                throwCompilerError "EXPECTED =", ASIS, 0
                tempSuccess = 0
              END IF
            END IF
          END IF
        END IF
      END IF

    CASE TOK_SUB
      IF lineTokenCount < startIdx + 2 THEN
        throwCompilerError "MALFORMED SUB", ASIS, 0
        tempSuccess = 0
      ELSE
        subName$ = UCASE$(lineTokens$(startIdx + 1))
        ff = findSubIndex(subName$)
        IF ff = 0 THEN
          throwCompilerError "SUB NOT FOUND", ASIS, 0
          tempSuccess = 0
        ELSE
          subIdx = returnedData2
          currentScopeID = subs(subIdx).ScopeID
          insideSub = 1
          currentSubName$ = subName$

          tira_Start
          tiraJmp "@SKIP_ROUTINE_" + subName$
          tiraSetSubOffset subIdx
          tiraScheduleSubPrologue
          tira_EndAndProcess
        END IF
      END IF

    CASE 0
      IF LEN(firstTok$) > 0 THEN
        firstChar$ = LEFT$(firstTok$, 1)
        IF (firstChar$ >= "A" AND firstChar$ <= "Z") OR (firstChar$ >= "a" AND firstChar$ <= "z") OR firstChar$ = "!" OR firstChar$ = "~" THEN

          assignRes = parseAssignRouter(startIdx)
          IF assignRes <> IMPLICIT_NOT_ASSIGN THEN
            IF assignRes = IMPLICIT_FAIL THEN
              tempSuccess = 0
            END IF
          ELSE
            subName$ = UCASE$(firstTok$)
            ff = findSymbol(subName$)

            IF ff = 1 THEN
              vIdx = returnedData2
              IF symbols(vIdx).SubIndex <> 0 THEN
                callRes = parseSubCall(startIdx, 0, vIdx)
                IF callRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                  tempSuccess = 0
                  IF compileStatusMsg$ = "" THEN throwCompilerError "CALL", WITHFAILED, 0
                END IF
              ELSE
                tempSuccess = 0
                isUnrecognized = 1
              END IF
            ELSE
              tempSuccess = 0
              isUnrecognized = 1
            END IF
          END IF
        ELSE
          tempSuccess = 0
          isUnrecognized = 1
        END IF
      ELSE
        tempSuccess = 0
        throwCompilerError "UNRECOGNIZED KEYWORD", ASIS, 0
      END IF

    CASE ELSE
      tempSuccess = 0
      isUnrecognized = 1

  END SELECT ' tVal

  IF isUnrecognized = 1 THEN
    errTokStr$ = retTokenText$(firstTok$)

    IF errTokStr$ <> "" THEN
      rawLineErr$ = compileText$(currentLineNumber)
      matchPosErr = 0
      inQuotesErr = 0
      FOR iScan = 1 TO LEN(rawLineErr$)
        chScan = MID$(rawLineErr$, iScan, 1)
        IF chScan = CHR$(34) THEN inQuotesErr = 1 - inQuotesErr
        IF inQuotesErr = 0 THEN
          IF MID$(rawLineErr$, iScan, LEN(errTokStr$)) = errTokStr$ THEN
            matchPosErr = iScan
            EXIT FOR
          END IF
        END IF
      NEXT

      IF matchPosErr > 0 THEN
        chunkStartErr = matchPosErr
        DO WHILE chunkStartErr > 1
          chPrevErr = MID$(rawLineErr$, chunkStartErr - 1, 1)
          IF chPrevErr = " " OR chPrevErr = CHR$(9) OR chPrevErr = ":" THEN EXIT DO
          chunkStartErr = chunkStartErr - 1
        LOOP
        chunkEndErr = matchPosErr
        DO WHILE chunkEndErr <= LEN(rawLineErr$)
          chNextErr = MID$(rawLineErr$, chunkEndErr, 1)
          IF chNextErr = " " OR chNextErr = CHR$(9) OR chNextErr = ":" THEN EXIT DO
          chunkEndErr = chunkEndErr + 1
        LOOP
        errTokStr$ = MID$(rawLineErr$, chunkStartErr, chunkEndErr - chunkStartErr)
      END IF
    END IF

    throwCompilerError "UNRECOGNIZED KEYWORD: " + errTokStr$, ASIS, 0
  END IF

  IF tempSuccess = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    EXIT FUNCTION
  END IF

  parseStatement = 1

END FUNCTION ' parseStatement

''''''''''''''''''''''''
FUNCTION parseSubCall (startIdx, isExplicit, passVIdx)

  DIM targetType AS LONG
  DIM lhsUdtIndex AS LONG
  DIM fieldCnt AS LONG
  DIM fieldOffset AS LONG
  DIM fieldSize AS LONG
  DIM fType AS LONG
  DIM argStartIdx AS LONG
  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM endIdx AS LONG
  DIM origEndIdx AS LONG
  DIM tokIdx AS LONG
  DIM argIdx AS LONG
  DIM hasParens AS LONG
  DIM exprEndIdx AS LONG
  DIM hasExprEnd AS LONG
  DIM targetVarIdx AS LONG
  DIM iField AS LONG
  DIM srcArgIdx AS LONG
  DIM srcAxIdx AS LONG
  DIM srcAyIdx AS LONG
  DIM tgtAxIdx AS LONG
  DIM tgtAyIdx AS LONG

  IF isExplicit = 1 THEN
    argStartIdx = startIdx + 2
  ELSE
    argStartIdx = startIdx + 1
  END IF

  IF passVIdx <> -1 THEN
    vIdx = passVIdx
    subName$ = RTRIM$(symbols(vIdx).RecordName)
  ELSE
    IF isExplicit = 1 THEN
      IF lineTokenCount < startIdx + 2 THEN
        throwCompilerError "EXPECTED SUB NAME", ASIS, 0
        EXIT FUNCTION
      END IF
      subName$ = UCASE$(lineTokens$(startIdx + 1))
    ELSE
      subName$ = UCASE$(lineTokens$(startIdx))
    END IF
    ff = resolveSymbol(subName$)
    IF ff = 0 THEN EXIT FUNCTION
    vIdx = returnedData2
  END IF

  subIdx = symbols(vIdx).SubIndex
  IF subIdx = 0 THEN
    throwCompilerError "SUB NOT FOUND", ASIS, 0
    EXIT FUNCTION
  END IF

  ff = findInstructionEnd(argStartIdx)
  IF ff = 0 THEN EXIT FUNCTION
  endIdx = returnedData2
  origEndIdx = endIdx

  tokIdx = argStartIdx
  argIdx = 0

  hasParens = 0
  IF tokIdx <= endIdx THEN
    IF lineTokenVals(tokIdx) = 256 + ASC("(") THEN
      IF findMatchingParen(tokIdx, endIdx) = 1 THEN
        IF returnedData2 = endIdx THEN
          hasParens = 1
          tokIdx = tokIdx + 1
          endIdx = endIdx - 1
        END IF
      END IF
    END IF
  END IF

  tira_Start

  DO WHILE tokIdx <= endIdx
    hasExprEnd = 0
    exprEndIdx = 0
    IF findNextTokenAtDepth0(tokIdx, endIdx, 256 + ASC(",")) = 1 THEN
      hasExprEnd = 1
      exprEndIdx = returnedData2
    END IF
    IF hasExprEnd = 0 THEN
      exprEndIdx = endIdx + 1
    END IF

    IF tokIdx > exprEndIdx - 1 THEN
      throwCompilerErrorAndCancelTira "MISSING ARGUMENT", ASIS, 0
      EXIT FUNCTION
    END IF

    IF argIdx >= subs(subIdx).ArgCount THEN
      throwCompilerErrorAndCancelTira "TOO MANY ARGS FOR " + subName$, ASIS, 0
      EXIT FUNCTION
    END IF

    targetVarIdx = subArgVarIdx(subIdx, argIdx)
    targetType = symbols(targetVarIdx).DataType

    IF targetType = TYPE_UDT THEN
      lhsUdtIndex = symbols(targetVarIdx).UDTIndex

      ' Call the isolated helper function to evaluate and validate the right side UDT
      rhsBase$ = tiraParseRhsUdtBase$(tokIdx, exprEndIdx - 1, lhsUdtIndex)
      IF rhsBase$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      lhsBase$ = tiraFrontendCalcAddress$(RTRIM$(symbols(targetVarIdx).RecordName), "", "", 0)
      IF lhsBase$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      fieldCnt = udts(lhsUdtIndex).FieldCount

      FOR iField = 0 TO fieldCnt - 1
        fieldOffset = udtFields(lhsUdtIndex, iField).Offset
        fieldSize = udtFields(lhsUdtIndex, iField).Size
        fType = udtFields(lhsUdtIndex, iField).DataType

        IF fType = TYPE_STRING AND udtFields(lhsUdtIndex, iField).IsDynamicString = 1 THEN
          rhsDescAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, rhsDescAddr$, rhsBase$, LTRIM$(STR$(fieldOffset))

          rhsDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraNew TC_READ_MEM, rhsDescPtr$ + ", " + rhsDescAddr$

          skipRhsNullArg$ = tiraLabelCreateNew$("SKIP_RHS_NULL_ARG")
          tiraJmpCond "JNE", rhsDescPtr$, "0", skipRhsNullArg$
          tiraAssign rhsDescPtr$, "!G_SYS_EMPTY_DESC$"
          tiraLabel skipRhsNullArg$

          lhsDescAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, lhsDescAddr$, lhsBase$, LTRIM$(STR$(fieldOffset))

          lhsDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraNew TC_READ_MEM, lhsDescPtr$ + ", " + lhsDescAddr$

          tiraEnsureStringAlloc lhsDescPtr$, lhsDescAddr$

          tiraCall "RT_STR_ASSIGN", 2, lhsDescPtr$ + ", " + rhsDescPtr$
        ELSE
          lhsFieldAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, lhsFieldAddr$, lhsBase$, LTRIM$(STR$(fieldOffset))

          rhsFieldAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
          tiraOp TC_ADD, rhsFieldAddr$, rhsBase$, LTRIM$(STR$(fieldOffset))

          tiraMemcpy lhsFieldAddr$, rhsFieldAddr$, LTRIM$(STR$(fieldSize))
        END IF
      NEXT iField
    ELSE
      argVar$ = tiraParseExpression$(tokIdx, exprEndIdx - 1, 1)
      IF argVar$ = "" THEN
        tira_Cancel
        EXIT FUNCTION
      END IF

      targetVarName$ = "#" + LTRIM$(STR$(targetVarIdx))

      IF symbols(targetVarIdx).IsArray = 2 THEN
        IF exprIs.DataType = TYPE_STRING AND targetType <> TYPE_STRING THEN
          throwCompilerErrorAndCancelTira "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
          EXIT FUNCTION
        END IF
        IF exprIs.DataType <> TYPE_STRING AND targetType = TYPE_STRING THEN
          throwCompilerErrorAndCancelTira "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
          EXIT FUNCTION
        END IF

        tiraAssign targetVarName$, argVar$

        srcArgName$ = UCASE$(lineTokens$(tokIdx))
        ff = resolveSymbol(srcArgName$)
        IF ff = 1 THEN
          srcArgIdx = returnedData2
          srcBase$ = RTRIM$(symbols(srcArgIdx).RecordName)
          tgtBase$ = RTRIM$(symbols(targetVarIdx).RecordName)

          ff = resolveSymbol("!G_SYS_" + srcBase$ + "_AX_VAL")
          IF ff = 1 THEN srcAxIdx = returnedData2
          ff = resolveSymbol("!G_SYS_" + srcBase$ + "_AY_VAL")
          IF ff = 1 THEN srcAyIdx = returnedData2
          ff = resolveSymbol("!G_SYS_" + tgtBase$ + "_AX_VAL")
          IF ff = 1 THEN tgtAxIdx = returnedData2
          ff = resolveSymbol("!G_SYS_" + tgtBase$ + "_AY_VAL")
          IF ff = 1 THEN tgtAyIdx = returnedData2

          tiraAssign "#" + LTRIM$(STR$(tgtAxIdx)), "#" + LTRIM$(STR$(srcAxIdx))
          tiraAssign "#" + LTRIM$(STR$(tgtAyIdx)), "#" + LTRIM$(STR$(srcAyIdx))
        END IF
      ELSE
        IF targetType = TYPE_STRING THEN
          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerErrorAndCancelTira "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
            EXIT FUNCTION
          END IF

          tiraCall "RT_STR_ASSIGN", 2, targetVarName$ + ", " + argVar$
        ELSE
          IF exprIs.DataType = TYPE_STRING THEN
            throwCompilerErrorAndCancelTira "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
            EXIT FUNCTION
          END IF

          tiraAssign targetVarName$, argVar$
        END IF
      END IF
    END IF

    argIdx = argIdx + 1
    tokIdx = exprEndIdx + 1
  LOOP

  IF argIdx < subs(subIdx).ArgCount THEN
    throwCompilerErrorAndCancelTira "TOO FEW ARGS FOR " + subName$, ASIS, 0
    EXIT FUNCTION
  END IF

  tiraCall subName$, 0, ""

  tiraScheduleHeapReset
  tira_EndAndProcess

  return2 origEndIdx
  parseSubCall = 1

END FUNCTION ' parseSubCall

''''''''''''''''''''''''
FUNCTION parseTypeClause (startTokIdx, endIdx)

  returnExtraPrepare

  DIM tempTokIdx AS LONG
  DIM tType AS LONG
  DIM dtMapped AS LONG
  DIM uTok$
  DIM sizeTok$
  DIM isNum AS LONG
  DIM fixedLen AS LONG
  DIM tempType AS LONG
  DIM typeData AS LONG
  DIM iCheck AS LONG
  DIM chCheck$
  DIM hasAsterisk AS LONG

  tempTokIdx = startTokIdx
  tempType = TYPE_UNDEFINED
  typeData = 0

  IF tempTokIdx <= endIdx THEN
    IF lineTokenVals(tempTokIdx) = TOK_UNSIGNED THEN
      tempTokIdx = tempTokIdx + 1
      IF tempTokIdx <= endIdx THEN
        tType = lineTokenVals(tempTokIdx)
        dtMapped = retTypeFromToken(tType, 1)

        IF dtMapped <> TYPE_UNDEFINED THEN
          tempTokIdx = tempTokIdx + 1
          tempType = dtMapped
        ELSE
          throwCompilerError "EXPECTED _BYTE, INTEGER, LONG, OR _INTEGER64 BUT GOT " + CHR$(34) + retTokenText$(lineTokens$(tempTokIdx)) + CHR$(34), ASIS, 0
        END IF
      ELSE
        throwCompilerError "EXPECTED TYPE AFTER _UNSIGNED", ASIS, 0
      END IF
    ELSE
      tType = lineTokenVals(tempTokIdx)
      dtMapped = retTypeFromToken(tType, 0)

      IF dtMapped <> TYPE_UNDEFINED THEN
        tempTokIdx = tempTokIdx + 1
        tempType = dtMapped

        SELECT CASE tType

          CASE TOK_DSTRING
            IF tempTokIdx <= endIdx THEN
              IF lineTokenVals(tempTokIdx) = 256 + ASC("*") THEN
                throwCompilerError "DSTRING CANNOT HAVE * LENGTH", ASIS, 0
                tempType = TYPE_UNDEFINED
              END IF
            END IF

          CASE TOK_STRING
            hasAsterisk = 0
            IF tempTokIdx <= endIdx THEN
              IF lineTokenVals(tempTokIdx) = 256 + ASC("*") THEN hasAsterisk = 1
            END IF

            IF hasAsterisk = 1 THEN
              tempTokIdx = tempTokIdx + 1
              IF tempTokIdx <= endIdx THEN
                sizeTok$ = lineTokens$(tempTokIdx)
                isNum = 1
                FOR iCheck = 1 TO LEN(sizeTok$)
                  chCheck$ = MID$(sizeTok$, iCheck, 1)
                  IF chCheck$ < "0" OR chCheck$ > "9" THEN
                    isNum = 0
                    EXIT FOR
                  END IF
                NEXT
                IF isNum = 0 THEN
                  throwCompilerError "STRING LENGTH MUST BE CONSTANT", ASIS, 0
                  tempType = TYPE_UNDEFINED
                ELSE
                  fixedLen = VAL(sizeTok$)
                  typeData = fixedLen
                  tempTokIdx = tempTokIdx + 1
                END IF
              ELSE
                throwCompilerError "EXPECTED STRING LENGTH", ASIS, 0
                tempType = TYPE_UNDEFINED
              END IF
            ELSE
              IF compileStringStrict = 1 THEN
                throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                tempType = TYPE_UNDEFINED
              END IF
            END IF

        END SELECT ' tType

      ELSE
        IF tType = 0 THEN ' UDT Identifier Match
          uTok$ = UCASE$(lineTokens$(tempTokIdx))
          ff = findUdtIndex(uTok$)
          IF ff = 1 THEN
            typeData = returnedData2
            tempTokIdx = tempTokIdx + 1
            tempType = TYPE_UDT
          ELSE
            throwCompilerError "UNSUPPORTED TYPE OR UNKNOWN UDT " + CHR$(34) + lineTokens$(tempTokIdx) + CHR$(34), ASIS, 0
          END IF
        ELSE
          throwCompilerError "UNSUPPORTED TYPE " + CHR$(34) + retTokenText$(lineTokens$(tempTokIdx)) + CHR$(34), ASIS, 0
        END IF
      END IF
    END IF
  ELSE
    throwCompilerError "EXPECTED TYPE", ASIS, 0
  END IF

  return3 typeData
  return2 tempType
  parseTypeClause = tempTokIdx

END FUNCTION ' parseTypeClause

''''''''''''''''''''''''
SUB pasteClipboardText

  IF editor.IsSelecting = 1 THEN
    deleteSelection
    editor.IsSelecting = 0
  END IF

  cbText$ = _CLIPBOARD$
  cbLen = LEN(cbText$)
  IF cbLen = 0 THEN EXIT SUB

  ' Pre-allocate a buffer to rapidly filter non-printable characters in a single O(N) pass
  cleanText$ = SPACE$(cbLen)
  cleanIdx = 1

  FOR ii = 1 TO cbLen
    cbAsc = ASC(cbText$, ii)
    ' Allow only newlines (10) and standard printable characters (32 to 126)
    IF cbAsc = 10 OR (cbAsc >= 32 AND cbAsc <= 126) THEN
      ASC(cleanText$, cleanIdx) = cbAsc
      cleanIdx = cleanIdx + 1
    END IF
  NEXT

  cbText$ = LEFT$(cleanText$, cleanIdx - 1)
  cbLen = LEN(cbText$)
  IF cbLen = 0 THEN EXIT SUB

  ' Count newlines to determine the exact array shift distance
  nlCount = 0
  ix = 1
  DO WHILE ix <= cbLen
    nextNl = INSTR(ix, cbText$, CHR$(10))
    IF nextNl > 0 THEN
      nlCount = nlCount + 1
      ix = nextNl + 1
    ELSE
      EXIT DO
    END IF
  LOOP

  ' Shift array down exactly once in bulk
  IF nlCount > 0 THEN
    FOR iy = editor.LastLine TO editor.CursorY + 1 STEP -1
      IF iy + nlCount <= EDITOR_LINE_MAX THEN
        editorText$(iy + nlCount) = editorText$(iy)
      END IF
    NEXT

    editor.LastLine = editor.LastLine + nlCount
    IF editor.LastLine > EDITOR_LINE_MAX THEN editor.LastLine = EDITOR_LINE_MAX
  END IF

  currentLine$ = editorText$(editor.CursorY)
  leftPart$ = LEFT$(currentLine$, editor.CursorX)
  rightPart$ = MID$(currentLine$, editor.CursorX + 1)

  ix = 1
  curPasteY = editor.CursorY
  linesPasted = 0

  ' Process the filtered clipboard and inject directly into the opened array spaces
  DO WHILE ix <= cbLen
    nextNl = INSTR(ix, cbText$, CHR$(10))
    IF nextNl = 0 THEN
      ' Final chunk of text (no trailing newline)
      chunk$ = MID$(cbText$, ix)
      IF curPasteY <= EDITOR_LINE_MAX THEN
        IF linesPasted = 0 THEN
          editorText$(curPasteY) = leftPart$ + chunk$ + rightPart$
          editor.CursorX = LEN(leftPart$ + chunk$)
        ELSE
          editorText$(curPasteY) = chunk$ + rightPart$
          editor.CursorX = LEN(chunk$)
        END IF
      END IF
      EXIT DO
    ELSE
      ' Extract line up to the newline
      chunk$ = MID$(cbText$, ix, nextNl - ix)
      IF curPasteY <= EDITOR_LINE_MAX THEN
        IF linesPasted = 0 THEN
          editorText$(curPasteY) = leftPart$ + chunk$
        ELSE
          editorText$(curPasteY) = chunk$
        END IF
      END IF

      linesPasted = linesPasted + 1
      curPasteY = curPasteY + 1
      ix = nextNl + 1
    END IF
  LOOP

  ' Handle edge case where clipboard ends exactly on a newline
  IF RIGHT$(cbText$, 1) = CHR$(10) THEN
    IF curPasteY <= EDITOR_LINE_MAX THEN
      editorText$(curPasteY) = rightPart$
      editor.CursorX = 0
    END IF
  END IF

  editor.CursorY = curPasteY
  IF editor.CursorY > EDITOR_LINE_MAX THEN
    editor.CursorY = EDITOR_LINE_MAX
    editor.CursorX = LEN(editorText$(EDITOR_LINE_MAX))
  END IF

  ' Update view scrolling
  IF editor.CursorY < editor.ScrollY THEN editor.ScrollY = editor.CursorY
  IF editor.CursorY >= editor.ScrollY + 28 THEN editor.ScrollY = editor.CursorY - 27
  IF editor.CursorX < editor.ScrollX THEN editor.ScrollX = editor.CursorX
  IF editor.CursorX >= editor.ScrollX + 56 THEN editor.ScrollX = editor.CursorX - 55

END SUB ' pasteClipboardText

''''''''''''''''''''''''
SUB patch8 (wPos)

  ' Calculates and patches an 8-bit short jump displacement
  ' Includes a safety check to prevent silent overflow crashes

  patchOffset = stream.emitPos - (wPos + 1)

  IF patchOffset > 127 OR patchOffset < -128 THEN
    ESCAPETEXT "FATAL COMPILER ERROR: 8-bit jump displacement out of bounds (" + LTRIM$(STR$(patchOffset)) + ") in patch8"
  END IF

  intermediateCode(wPos) = patchOffset AND 255

END SUB ' patch8

''''''''''''''''''''''''
SUB patch32 (wPos, wVal AS LONG)

  DIM uVal AS _UNSIGNED LONG

  uVal = wVal
  intermediateCode(wPos) = uVal AND 255
  intermediateCode(wPos + 1) = (uVal \ 256) AND 255
  intermediateCode(wPos + 2) = (uVal \ 65536) AND 255
  intermediateCode(wPos + 3) = (uVal \ 16777216) AND 255

END SUB ' patch32

''''''''''''''''''''''''
''''''''''''''''''''''''
SUB prepareBinary

  DIM prologueBoundary AS LONG

  compilePass6GlobalMap

  outputFileIdx = 0

  rwVar$ = " " ' Necessary

  userCodeLen = stream.emitPos
  DIM userCode(userCodeLen + 1) AS _UNSIGNED _BYTE
  FOR ii = 0 TO userCodeLen - 1
    userCode(ii) = intermediateCode(ii)
  NEXT
  stream.emitPos = 0

  IF compileHasGraphics = 0 THEN
    userPatchCount = patchCount
    userIatPatchCount = iatPatchCount
    userGotoPatchCount = gotoPatchCount
    userCallPatchCount = callPatchCount
    userRtPatchCount = rt.PatchCount
    userSubCount = subCount
    userSymbolCount = symbolCount

    emitPrologue
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    prologueBoundary = stream.emitPos
    adjustAllPatchOffsets prologueBoundary, userPatchCount, userIatPatchCount, userGotoPatchCount, userCallPatchCount, userRtPatchCount, userSubCount, userSymbolCount

    FOR ii = 0 TO userCodeLen - 1
      intermediateCode(stream.emitPos) = userCode(ii)
      stream.emitPos = stream.emitPos + 1
    NEXT

  ELSE
    userPatchCount = patchCount
    userIatPatchCount = iatPatchCount
    userGotoPatchCount = gotoPatchCount
    userCallPatchCount = callPatchCount
    userRtPatchCount = rt.PatchCount
    userSubCount = subCount
    userSymbolCount = symbolCount

    IF USE_DIB_SECTION = 1 THEN
      ESCAPETEXT "USE_DIB_SECTION SET TO 1, HARDWARE GRAPHICS NOT SUPPORTED YET"
    ELSE
      emitPrologueWindowSetup
    END IF
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    emitPrologue
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    prologueBoundary = stream.emitPos
    adjustAllPatchOffsets prologueBoundary, userPatchCount, userIatPatchCount, userGotoPatchCount, userCallPatchCount, userRtPatchCount, userSubCount, userSymbolCount

    FOR ii = 0 TO userCodeLen - 1
      intermediateCode(stream.emitPos) = userCode(ii)
      stream.emitPos = stream.emitPos + 1
    NEXT

  END IF

  ff = resolveSymbol("@END_PROGRAM")
  IF ff = 1 THEN
    vIdx = returnedData2
    symbols(vIdx).DataType = TYPE_LABEL
    symbols(vIdx).Offset = stream.emitPos
  END IF

  emitEpilogue
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  gfxBufTotalSize = 4096 * layout.GfxBufEntrySize

  textLayout.CodeOffset = PE_FILE_HEADER_OFFSET
  textLayout.CodeSize = stream.emitPos
  textLayout.StrBase = textLayout.CodeOffset + textLayout.CodeSize
  textLayout.VarBase = textLayout.StrBase + textLayout.TotalStrSize
  textLayout.DescBase = textLayout.VarBase + textLayout.TotalVarSize
  textLayout.GfxBufFrontBase = textLayout.DescBase + textLayout.TotalDescSize
  textLayout.GfxBufBackBase = textLayout.GfxBufFrontBase + gfxBufTotalSize
  textLayout.HwndBase = textLayout.GfxBufBackBase + gfxBufTotalSize
  textLayout.MemDCBase = textLayout.HwndBase + 8
  textLayout.DIBPtrBase = textLayout.MemDCBase + 8
  textLayout.HBitmapBase = textLayout.DIBPtrBase + 8
  textLayout.FramebufFrontBase = textLayout.HBitmapBase + 8
  textLayout.FramebufBackBase = textLayout.FramebufFrontBase + layout.FramebufSize
  textLayout.KbdBufBase = textLayout.FramebufBackBase + layout.FramebufSize
  textLayout.KbdHeadBase = textLayout.KbdBufBase + 256
  textLayout.KbdTailBase = textLayout.KbdHeadBase + 8
  textLayout.FileHandlesBase = textLayout.KbdTailBase + 8
  textLayout.DataPtrArrBase = textLayout.FileHandlesBase + 2048
  textLayout.KbdStateBase = textLayout.DataPtrArrBase + (dataItemCount * 8)
  textLayout.MouseBufBase = textLayout.KbdStateBase + 256
  textLayout.MouseHeadBase = textLayout.MouseBufBase + 8192
  textLayout.MouseTailBase = textLayout.MouseHeadBase + 8
  textLayout.TotalSize = (textLayout.MouseTailBase + 8) - textLayout.CodeOffset

  ff = resolveSymbol("!G_LAYOUT_GFX_BUF_FRONT_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.GfxBufFrontBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_GFX_BUF_BACK_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.GfxBufBackBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_FRAMEBUF_FRONT_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.FramebufFrontBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_FRAMEBUF_BACK_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.FramebufBackBase - textLayout.VarBase

  ff = resolveSymbol("!G_LAYOUT_HWND_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.HwndBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_KBD_HEAD_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.KbdHeadBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_KBD_TAIL_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.KbdTailBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_KBD_BUF_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.KbdBufBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_KBD_STATE_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.KbdStateBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_MEMDC_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.MemDCBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_DIB_PTR_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.DIBPtrBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_HBITMAP_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.HBitmapBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_FILE_HANDLES_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.FileHandlesBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_DATA_PTR_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.DataPtrArrBase - textLayout.VarBase

  ff = resolveSymbol("!G_LAYOUT_MOUSE_BUF_ARR"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.MouseBufBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_MOUSE_HEAD_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.MouseHeadBase - textLayout.VarBase
  ff = resolveSymbol("!G_LAYOUT_MOUSE_TAIL_VAL"): IF ff = 1 THEN symbols(returnedData2).Offset = textLayout.MouseTailBase - textLayout.VarBase

  wTextRawSize = (((textLayout.TotalSize) + PE_FILE_ALIGNMENT - 1) \ PE_FILE_ALIGNMENT) * PE_FILE_ALIGNMENT
  localIdataRVA = ((PE_TEXT_RVA + textLayout.TotalSize + PE_SECTION_ALIGNMENT - 1) \ PE_SECTION_ALIGNMENT) * PE_SECTION_ALIGNMENT

  impTbl.baseRVA = localIdataRVA
  buildImportTable

  FOR ii = 0 TO patchCount - 1
    pOffEmit = patches(ii).Offset
    vIdx = patches(ii).VarIdx

    actualVarOffset = textLayout.VarBase + symbols(vIdx).Offset
    varRVA = textFileRVA(actualVarOffset)

    ripAfter = PE_TEXT_VA + pOffEmit + 4
    disp = varRVA - ripAfter

    patch32 pOffEmit, disp
  NEXT

  FOR ii = 0 TO iatPatchCount - 1
    pOffEmit = iatPatches(ii).Offset
    iatConst = iatPatches(ii).IATIdx
    mappedIdx = impIatFlatIdx(iatConst)

    iatEntryRVA = PE_IMAGE_BASE + impFlatIatRVA(mappedIdx)

    ripAfter = PE_TEXT_VA + pOffEmit + 4
    disp = iatEntryRVA - ripAfter

    patch32 pOffEmit, disp
  NEXT

  FOR ii = 0 TO gotoPatchCount - 1
    pOffEmit = gotoPatches(ii).Offset
    vIdx = gotoPatches(ii).VarIdx
    targetOffset = symbols(vIdx).Offset

    disp = targetOffset - (pOffEmit + 4)
    patch32 pOffEmit, disp
  NEXT

  FOR ii = 0 TO callPatchCount - 1
    pOffEmit = callPatches(ii).Offset
    targetSubIdx = callPatches(ii).SubIndex
    targetOffset = subs(targetSubIdx).Offset

    IF targetOffset < prologueBoundary OR targetOffset >= stream.emitPos THEN
      targetName$ = RTRIM$(subs(targetSubIdx).RecordName)
      addStatusMsg "ERROR: GPF FATAL: SUB " + targetName$ + " TARGET OUT OF BOUNDS"
      compileStatusMsg$ = "ERROR: GPF FATAL"
      EXIT SUB
    END IF

    targetOpcode = intermediateCode(targetOffset)
    IF targetOpcode <> &H55 THEN
      targetName$ = RTRIM$(subs(targetSubIdx).RecordName)
      addStatusMsg "ERROR: GPF FATAL: SUB " + targetName$ + " OFFSET DOES NOT POINT TO FUNCTION START"
      compileStatusMsg$ = "ERROR: GPF FATAL"
      EXIT SUB
    END IF

    disp = targetOffset - (pOffEmit + 4)
    patch32 pOffEmit, disp
  NEXT

  FOR ii = 0 TO rt.PatchCount - 1
    pOffEmit = rtPatches(ii).Offset
    targetOffset = rtOffset(rtPatches(ii).Routine)

    IF targetOffset < prologueBoundary OR targetOffset >= stream.emitPos THEN
      addStatusMsg "ERROR: GPF FATAL: RT HELPER " + LTRIM$(STR$(rtPatches(ii).Routine)) + " TARGET OUT OF BOUNDS"
      compileStatusMsg$ = "ERROR: GPF FATAL"
      EXIT SUB
    END IF

    targetOpcode = intermediateCode(targetOffset)
    IF targetOpcode <> &H55 AND targetOpcode <> &H53 THEN
      addStatusMsg "ERROR: GPF FATAL: RT HELPER " + LTRIM$(STR$(rtPatches(ii).Routine)) + " TARGET INVALID (OPCODE $" + HEX$(targetOpcode) + ")"
      compileStatusMsg$ = "ERROR: GPF FATAL"
      EXIT SUB
    END IF

    disp = targetOffset - (pOffEmit + 4)
    patch32 pOffEmit, disp
  NEXT

  writePEHeader wTextRawSize

  FOR ii = 0 TO stream.emitPos - 1
    outputFile(outputFileIdx) = intermediateCode(ii)
    outputFileIdx = outputFileIdx + 1
  NEXT

  arrayPadUpTo textLayout.StrBase, 0
  FOR ii = 0 TO symbolCount - 1
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
    ELSE
      IF symbols(ii).DataType = TYPE_STRING AND symbols(ii).IsArray = 0 THEN
        IF strVarData$(ii) <> "" THEN
          strData$ = strVarData$(ii)
          strLen = LEN(strData$)
          FOR i2 = 1 TO strLen
            outputFile(outputFileIdx) = ASC(MID$(strData$, i2, 1))
            outputFileIdx = outputFileIdx + 1
          NEXT
          outputFile(outputFileIdx) = 0
          outputFileIdx = outputFileIdx + 1
        END IF
      END IF
    END IF
  NEXT

  arrayPadUpTo textLayout.VarBase, 0
  FOR ii = 0 TO symbolCount - 1
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
    ELSE
      IF symbols(ii).IsArray = 2 THEN
        arrayPadNumBytes 8, 0
      ELSE
        IF symbols(ii).DataType = TYPE_DOUBLE AND floatVarData(ii) <> 0 AND symbols(ii).IsArray = 0 THEN
          arrayWrite64F floatVarData(ii)
        ELSE
          IF symbols(ii).DataType = TYPE_SINGLE AND floatVarData(ii) <> 0 AND symbols(ii).IsArray = 0 THEN
            arrayWrite32F floatVarData(ii)
            arrayPadNumBytes 4, 0
          ELSE
            IF symbols(ii).DataType = TYPE_STRING THEN
              IF symbols(ii).IsArray = 1 THEN
                fixedLen = symbols(ii).FixedStrLen

                IF fixedLen > 0 THEN
                  arrayPadNumBytes retSymbolByteSize(ii), 32
                ELSE
                  arrayPadNumBytes retSymbolByteSize(ii), 0
                END IF
              ELSE
                descVA = textFileRVA(textLayout.DescBase + symbols(ii).DescOffset)
                arrayWrite32LE descVA
                arrayWrite32LE 0
              END IF
            ELSE
              arrayPadNumBytes retSymbolByteSize(ii), 0
            END IF
          END IF
        END IF
      END IF
    END IF
  NEXT

  arrayPadUpTo textLayout.DescBase, 0
  FOR ii = 0 TO symbolCount - 1
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
    ELSE
      IF symbols(ii).DataType = TYPE_STRING AND symbols(ii).IsArray = 0 THEN
        IF strVarData$(ii) <> "" THEN
          strVA = textFileRVA(textLayout.StrBase + symbols(ii).StrOffset)
          strLen = LEN(strVarData$(ii))
          arrayWrite32LE strVA
          arrayWrite32LE 0
          arrayWrite32LE strLen
          arrayWrite32LE 0
          arrayWrite32LE 0
          arrayWrite32LE 0
        ELSE
          strVA = textFileRVA(textLayout.StrBase)
          arrayWrite32LE strVA
          arrayWrite32LE 0
          arrayWrite32LE 0
          arrayWrite32LE 0
          arrayWrite32LE 0
          arrayWrite32LE 0
        END IF
      END IF
    END IF
  NEXT

  arrayPadUpTo textLayout.GfxBufFrontBase, 0
  arrayPadNumBytes gfxBufTotalSize, 0
  arrayPadUpTo textLayout.GfxBufBackBase, 0
  arrayPadNumBytes gfxBufTotalSize, 0

  arrayPadUpTo textLayout.HwndBase, 0
  arrayWrite32LE 0
  arrayWrite32LE 0

  arrayWrite32LE 0
  arrayWrite32LE 0

  arrayWrite32LE 0
  arrayWrite32LE 0

  arrayWrite32LE 0
  arrayWrite32LE 0

  arrayPadUpTo textLayout.FramebufFrontBase, 0
  arrayPadNumBytes layout.FramebufSize, 0
  arrayPadUpTo textLayout.FramebufBackBase, 0
  arrayPadNumBytes layout.FramebufSize, 0

  arrayPadUpTo textLayout.FileHandlesBase, 0
  arrayPadNumBytes 2048, 0

  arrayPadUpTo textLayout.DataPtrArrBase, 0
  FOR j = 0 TO dataItemCount - 1
    descVA = textFileRVA(textLayout.DescBase + symbols(dataItemDescIdx(j)).DescOffset)
    arrayWrite32LE descVA
    arrayWrite32LE 0
  NEXT

  arrayPadUpTo textLayout.KbdStateBase, 0
  arrayPadNumBytes 256, 0

  arrayPadUpTo textLayout.MouseBufBase, 0
  arrayPadNumBytes 8192, 0

  arrayPadUpTo textLayout.MouseHeadBase, 0
  arrayWrite32LE 0
  arrayWrite32LE 0

  arrayPadUpTo textLayout.MouseTailBase, 0
  arrayWrite32LE 0
  arrayWrite32LE 0

  arrayPadUpTo PE_FILE_HEADER_OFFSET + wTextRawSize, 0

  writeIdataSection wTextRawSize

END SUB ' prepareBinary

''''''''''''''''''''''''
SUB PrintChr (wPosPixelsX, wPosPixelsY, wStr$, fgClr, bgClr, useTransparent)

  IF LEN(wStr$) <> 1 THEN
    ESCAPETEXT "ERROR: Only send one character to PrintChr. Character string sent was '" + wStr$ + "'"
  END IF

  wTile = ASC(wStr$)

  offsetY = wTile \ 16
  offsetX = wTile AND 15

  FOR iy = 0 TO 7
    FOR ix = 0 TO 7
      drawPosX = (wPosPixelsX + ix)
      drawPosY = (wPosPixelsY + iy)

      wClr = fontData((offsetX * 8) + ix, (offsetY * 8) + iy)

      IF wClr = 0 THEN
        IF useTransparent = 0 THEN
          PSET (drawPosX, drawPosY), bgClr
        END IF
      ELSE
        IF wClr = 15 THEN
          PSET (drawPosX, drawPosY), fgClr
        ELSE
          PSET (drawPosX, drawPosY), wClr
        END IF
      END IF
    NEXT
  NEXT

END SUB ' PrintChr

''''''''''''''''''''''''
SUB PrintStr (wPosPixelsX, wPosPixelsY, wStr$, fgClr, bgClr, useTransparent)

  FOR ii = 1 TO LEN(wStr$)
    toSend$ = MID$(wStr$, ii, 1)
    PrintChr wPosPixelsX - 8 + (ii * 8), wPosPixelsY, toSend$, fgClr, bgClr, useTransparent
  NEXT

END SUB ' PrintStr

''''''''''''''''''''''''
SUB PrintTextLineWithBanners (text$, wClr, whereY)

  paddingPixels = 8

  textStartX = 9

  SELECT CASE whereY

    CASE TOP: textStartY = 4
    CASE MIDDLE: textStartY = 20
    CASE BOTTOM: textStartY = 30

  END SELECT ' whereY

  textPixelWidth = LEN(text$) * 8
  boxPixelWidth = paddingPixels + textPixelWidth + paddingPixels
  boxPixelHeight = paddingPixels + 8 + paddingPixels

  boxStartX = (textStartX * 8) - paddingPixels
  boxStartY = (textStartY * 8) - paddingPixels

  IF (boxStartX + boxPixelWidth) >= SCREENSIZEX THEN
    boxStartX = SCREENSIZEX - boxPixelWidth
  END IF

  textStartX = (boxStartX + paddingPixels) \ 8

  IF (textStartX * 8) + textPixelWidth >= SCREENSIZEX THEN textStartX = 1

  boxStartX = (textStartX * 8) - paddingPixels

  drawBorderBox boxStartX, boxStartY, boxPixelWidth, boxPixelHeight, 1, 0
  drawClearBox boxStartX + 1, boxStartY + 1, boxPixelWidth - 2, boxPixelHeight - 2, 15

  PrintStr boxStartX + paddingPixels, boxStartY + paddingPixels, text$, wClr, 0, 0

END SUB ' PrintTextLineWithBanners

''''''''''''''''''''''''
SUB processCompileState

  SELECT CASE compileState

    CASE COMP_REFINE
      refineCode 1
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        compileState = COMP_IDLE
      ELSE
        addStatusMsg "COMPILING (PASS 1-4)..."
        compileState = COMP_COMPILE
        pass5.SubState = 0
      END IF

    CASE COMP_COMPILE

      SELECT CASE pass5.SubState

        CASE 0
          compRes = compile
          IF compRes = 1 THEN
            addStatusMsg "DISCOVERING SYMBOLS (PASS 5A)..."
            isDummyPass = 1
            stream.emitPos = 0

            ' Dry-run the setup and epilogue blocks to ensure their TIRA variables
            ' are generated and added to the symbol table BEFORE the global mapping pass
            IF compileHasGraphics = 1 THEN
              IF USE_DIB_SECTION = 1 THEN
                ESCAPETEXT "USE_DIB_SECTION SET TO 1, HARDWARE GRAPHICS NOT SUPPORTED YET"
              ELSE
                emitPrologueWindowSetup
              END IF
            END IF

            emitPrologue
            emitEpilogue

            stream.emitPos = 0 ' Reset stream.emitPos for the actual Dummy Pass layout
            t.TiraVarCounter = 0 ' Synchronize TIRA labels

            emitRuntimeAll
            pass5.SubState = 1
            pass5.Line = 1
            pass5.Success = 1
          ELSE
            compileState = COMP_IDLE
          END IF

        CASE 1
          compilePass5ScanOrEmit
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" OR pass5.Success = 0 THEN
            compileState = COMP_IDLE
          ELSE
            IF pass5.SubState = 2 THEN
              ' Dummy pass complete. Safely run pre-emission local layouts
              compilePass5bLocalVariables

              addStatusMsg "GENERATING CODE (PASS 5B+)..."
              isDummyPass = 0
              stream.emitPos = 0
              patchCount = 0
              iatPatchCount = 0
              gotoPatchCount = 0
              callPatchCount = 0
              rt.PatchCount = 0
              ctrlCount = 0
              t.TiraVarCounter = 0

              emitRuntimeAll

              pass5.SubState = 3
              pass5.Line = 1
              pass5.Success = 1
            END IF
          END IF

        CASE 3
          compilePass5ScanOrEmit
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" OR pass5.Success = 0 THEN
            compileState = COMP_IDLE
          ELSE
            IF pass5.SubState = 2 THEN
              addStatusMsg "SAVING..."
              compileState = COMP_SAVE
            END IF
          END IF

      END SELECT ' pass5.SubState

    CASE COMP_SAVE
      prepareBinary
      IF LEFT$(compileStatusMsg$, 5) <> "ERROR" THEN
        fileSaveBinary

        ' Only print SUCCESS and run the program if fileSaveBinary didn't throw a file lock error
        IF LEFT$(compileStatusMsg$, 5) <> "ERROR" THEN
          succMsg$ = "SUCCESS (Prologue: " + LTRIM$(STR$(metrics.PrologueSize)) + "b, Epilogue: " + LTRIM$(STR$(metrics.EpilogueSize)) + "b)"
          addStatusMsg succMsg$

          runCmd$ = CHR$(34) + fileNameOut$ + CHR$(34)
          SHELL _DONTWAIT runCmd$
        END IF
      END IF
      compileState = COMP_IDLE

  END SELECT ' compileState

END SUB ' processCompileState

''''''''''''''''''''''''
FUNCTION processDropdownMenu (wPosX, wPosY, wItemCount, passItems$())

  returnExtraPrepare

  DIM itemH AS LONG
  itemH = 14

  maxWidth = 0
  FOR ii = 0 TO wItemCount - 1
    wLen = LEN(passItems$(ii)) * 8
    IF LEFT$(passItems$(ii), 1) = "~" THEN wLen = wLen - 8
    IF wLen > maxWidth THEN maxWidth = wLen
  NEXT
  boxW = maxWidth + 16
  boxH = (wItemCount * itemH) + 2

  drawBorderBox wPosX, wPosY, boxW, boxH, 15, editor.windowBarClr

  itemSelected = 0
  clickedItem = 0

  FOR ii = 0 TO wItemCount - 1
    itemY = wPosY + 2 + (ii * itemH)
    dStr$ = passItems$(ii)
    isDisabled = 0
    IF LEFT$(dStr$, 1) = "~" THEN
      isDisabled = 1
      dStr$ = MID$(dStr$, 2)
    END IF

    IF isDisabled = 0 THEN
      IF mouseWithinBoxBounds(wPosX + 2, itemY, boxW - 4, itemH) THEN
        drawClearBox wPosX + 2, itemY, boxW - 4, itemH, 9
        IF mouseClickedInBox(wPosX + 2, itemY, boxW - 4, itemH) THEN
          clickedItem = ii
          itemSelected = 1
        END IF
      END IF
      PrintStr wPosX + 8, itemY + 2, dStr$, 15, 0, 1
    ELSE
      PrintStr wPosX + 8, itemY + 2, dStr$, sysColor.gray, 0, 1
    END IF
  NEXT

  IF mouseClickedInBox(wPosX, wPosY, boxW, boxH) THEN
    editor.MenuClicked = 1
  END IF

  IF itemSelected = 1 THEN
    return2 clickedItem
    processDropdownMenu = 1
  END IF

END FUNCTION ' processDropdownMenu

''''''''''''''''''''''''
SUB processInput

  IF keyCheck("ESC") THEN
    IF editor.MenuMode = 1 THEN
      editor.MenuMode = 0
      waitKeyRelease "ESC"
    ELSE
      IF _KEYDOWN(100303) OR _KEYDOWN(100304) THEN
        waitKeyRelease "ESC"
        confirmExit
      END IF
    END IF
  END IF

  IF keyCheck("F5") THEN
    waitKeyRelease "F5"
    IF compileState = COMP_IDLE THEN
      statusMsgCount = 1
      editor.StatusScrollY = 1
      editor.StatusSelectedIndex = 0
      FOR ii = 1 TO 999
        statusMsg$(ii) = ""
      NEXT
      compileState = COMP_REFINE
      addStatusMsg "REFINING..."
    END IF
  END IF

  IF (_KEYDOWN(100306) OR _KEYDOWN(100305)) AND keyCheck("F") THEN
    waitKeyRelease "F"
    searchModal
  END IF

  IF keyCheck("F3") THEN
    waitKeyRelease "F3"
    IF editorSearchQuery$ <> "" THEN
      findEditorNext
    ELSE
      searchModal
    END IF
  END IF

  kVal = _KEYHIT
  IF kVal = 0 THEN EXIT SUB

  IF editor.Focus = 2 THEN
    ' Ctrl+C (Copy)
    IF kVal = 3 OR ((kVal = 99 OR kVal = 67) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      IF editor.StatusSelectedIndex <> 0 THEN
        _CLIPBOARD$ = statusMsg$(editor.StatusSelectedIndex)
      END IF
      kVal = 0
    END IF

    ' Ctrl+X (Cut) - Treat as copy for status bar
    IF kVal = 24 OR ((kVal = 120 OR kVal = 88) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      IF editor.StatusSelectedIndex <> 0 THEN
        _CLIPBOARD$ = statusMsg$(editor.StatusSelectedIndex)
      END IF
      kVal = 0
    END IF
  END IF

  IF editor.Focus = 1 THEN

    lastLine = editor.LastLine
    IF editor.CursorY > lastLine THEN lastLine = editor.CursorY

    oldCursorY = editor.CursorY

    ' Ctrl+Z (Undo)
    IF kVal = 26 OR ((kVal = 122 OR kVal = 90) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      undo_StateRestore
      kVal = 0
      lastActionWasTyping = 0
    END IF

    ' Ctrl+C (Copy)
    IF kVal = 3 OR ((kVal = 99 OR kVal = 67) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      IF editor.IsSelecting = 1 THEN
        copyText$ = retEditorSelection$
        IF copyText$ <> "" THEN _CLIPBOARD$ = copyText$
      END IF
      kVal = 0
    END IF

    ' Ctrl+X (Cut)
    IF kVal = 24 OR ((kVal = 120 OR kVal = 88) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      IF editor.IsSelecting = 1 THEN
        undo_StateSave
        lastActionWasTyping = 0
        copyText$ = retEditorSelection$
        IF copyText$ <> "" THEN _CLIPBOARD$ = copyText$
        deleteSelection
        editor.IsSelecting = 0
      END IF
      kVal = 0
    END IF

    ' Ctrl+A (Select All)
    IF kVal = 1 OR ((kVal = 97 OR kVal = 65) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      editor.SelectStartX = 0
      editor.SelectStartY = 1
      editor.CursorY = editor.LastLine
      editor.CursorX = LEN(editorText$(editor.LastLine))
      editor.IsSelecting = 1
      kVal = 0
    END IF

    isMoveKey = 0
    IF kVal = 19200 OR kVal = 19712 OR kVal = 18432 OR kVal = 20480 OR kVal = 18176 OR kVal = 20224 OR kVal = 18688 OR kVal = 20736 THEN isMoveKey = 1

    IF isMoveKey = 1 THEN
      lastActionWasTyping = 0
      IF _KEYDOWN(100303) OR _KEYDOWN(100304) THEN
        IF editor.IsSelecting = 0 THEN
          editor.SelectStartX = editor.CursorX
          editor.SelectStartY = editor.CursorY
          editor.IsSelecting = 1
        END IF
      ELSE
        editor.IsSelecting = 0
      END IF
    END IF

    IF (kVal >= 32 AND kVal <= 126) OR kVal = 8 OR kVal = 212231 OR kVal = 21248 OR kVal = 13 OR kVal = 118 THEN
      IF isMoveKey = 0 AND kVal <> 0 THEN
        IF editor.IsSelecting = 1 THEN
          undo_StateSave
          IF (kVal >= 32 AND kVal <= 126) THEN
            lastActionWasTyping = 1
          ELSE
            lastActionWasTyping = 0
          END IF

          IF kVal = 8 OR kVal = 212231 OR kVal = 21248 THEN
            deleteSelection
            editor.IsSelecting = 0
            kVal = 0 ' Consume key to prevent normal backspace/delete
          ELSE
            IF (kVal >= 32 AND kVal <= 126) OR kVal = 13 THEN
              deleteSelection
              editor.IsSelecting = 0
            ELSE
              editor.IsSelecting = 0
            END IF
          END IF
        END IF
      END IF
    END IF

    IF kVal = 118 AND (_KEYDOWN(100306) OR _KEYDOWN(100305)) THEN ' Ctrl+V (Paste)
      IF editor.IsSelecting = 0 THEN undo_StateSave
      lastActionWasTyping = 0
      pasteClipboardText
      kVal = 0
    END IF

    IF kVal >= 32 AND kVal <= 126 THEN ' Printable character
      IF lastActionWasTyping = 0 THEN undo_StateSave
      lastActionWasTyping = 1
      currentLine$ = editorText$(editor.CursorY)
      leftPart$ = LEFT$(currentLine$, editor.CursorX)
      rightPart$ = MID$(currentLine$, editor.CursorX + 1)
      editorText$(editor.CursorY) = leftPart$ + CHR$(kVal) + rightPart$
      editor.CursorX = editor.CursorX + 1
    END IF

    IF kVal = 8 THEN ' Backspace
      undo_StateSave
      lastActionWasTyping = 0
      IF editor.CursorX > 0 THEN ' Delete character to the left
        currentLine$ = editorText$(editor.CursorY)
        leftPart$ = LEFT$(currentLine$, editor.CursorX - 1)
        rightPart$ = MID$(currentLine$, editor.CursorX + 1)
        editorText$(editor.CursorY) = leftPart$ + rightPart$
        editor.CursorX = editor.CursorX - 1
      ELSE
        IF editor.CursorY > 1 THEN ' Merge with previous line
          prevLineLen = LEN(editorText$(editor.CursorY - 1))
          editor.CursorX = prevLineLen
          editorText$(editor.CursorY - 1) = editorText$(editor.CursorY - 1) + editorText$(editor.CursorY)
          FOR ii = editor.CursorY TO editor.LastLine - 1
            editorText$(ii) = editorText$(ii + 1)
          NEXT
          editorText$(editor.LastLine) = ""
          editor.CursorY = editor.CursorY - 1
          editor.LastLine = editor.LastLine - 1
          IF editor.LastLine < 1 THEN editor.LastLine = 1
        END IF
      END IF
    END IF

    IF kVal = 212231 OR kVal = 21248 THEN ' Delete key
      undo_StateSave
      lastActionWasTyping = 0
      currentLine$ = editorText$(editor.CursorY)
      IF editor.CursorX < LEN(currentLine$) THEN ' Delete character to the right
        leftPart$ = LEFT$(currentLine$, editor.CursorX)
        rightPart$ = MID$(currentLine$, editor.CursorX + 2)
        editorText$(editor.CursorY) = leftPart$ + rightPart$
      ELSE
        IF editor.CursorY < lastLine THEN ' Merge next line into current
          editorText$(editor.CursorY) = currentLine$ + editorText$(editor.CursorY + 1)
          FOR ii = editor.CursorY + 1 TO editor.LastLine - 1
            editorText$(ii) = editorText$(ii + 1)
          NEXT
          editorText$(editor.LastLine) = ""
          editor.LastLine = editor.LastLine - 1
          IF editor.LastLine < 1 THEN editor.LastLine = 1
        END IF
      END IF
    END IF

    IF kVal = 13 THEN ' Enter key, split line at cursor
      undo_StateSave
      lastActionWasTyping = 0
      IF editor.CursorY < EDITOR_LINE_MAX THEN
        currentLine$ = editorText$(editor.CursorY)
        leftPart$ = LEFT$(currentLine$, editor.CursorX)
        rightPart$ = MID$(currentLine$, editor.CursorX + 1)
        editorText$(editor.CursorY) = leftPart$
        FOR ii = editor.LastLine TO editor.CursorY + 1 STEP -1
          IF ii < EDITOR_LINE_MAX THEN
            editorText$(ii + 1) = editorText$(ii)
          END IF
        NEXT
        editorText$(editor.CursorY + 1) = rightPart$
        editor.CursorY = editor.CursorY + 1
        editor.CursorX = 0
        editor.LastLine = editor.LastLine + 1
        IF editor.LastLine > EDITOR_LINE_MAX THEN editor.LastLine = EDITOR_LINE_MAX
        refineCode (0)
      END IF
    END IF

    IF kVal = 19200 THEN ' Left arrow
      IF editor.CursorX > 0 THEN
        editor.CursorX = editor.CursorX - 1
      ELSE
        IF editor.CursorY > 1 THEN ' Wrap to end of previous line
          editor.CursorY = editor.CursorY - 1
          editor.CursorX = LEN(editorText$(editor.CursorY))
        END IF
      END IF
    END IF

    IF kVal = 19712 THEN ' Right arrow
      IF editor.CursorX < LEN(editorText$(editor.CursorY)) THEN
        editor.CursorX = editor.CursorX + 1
      ELSE
        IF editor.CursorY < lastLine THEN ' Wrap to start of next line
          editor.CursorY = editor.CursorY + 1
          editor.CursorX = 0
        END IF
      END IF
    END IF

    IF kVal = 18432 THEN ' Up arrow
      IF editor.CursorY > 1 THEN
        editor.CursorY = editor.CursorY - 1
        IF editor.CursorX > LEN(editorText$(editor.CursorY)) THEN
          editor.CursorX = LEN(editorText$(editor.CursorY))
        END IF
      END IF
    END IF

    IF kVal = 20480 THEN ' Down arrow
      IF editor.CursorY < lastLine THEN
        editor.CursorY = editor.CursorY + 1
        IF editor.CursorX > LEN(editorText$(editor.CursorY)) THEN
          editor.CursorX = LEN(editorText$(editor.CursorY))
        END IF
      END IF
    END IF

    IF kVal = 18176 THEN ' Home key, go to start of line
      editor.CursorX = 0
    END IF

    IF kVal = 20224 THEN ' End key, go to end of line
      editor.CursorX = LEN(editorText$(editor.CursorY))
    END IF

    IF kVal = 18688 THEN ' Page up
      IF _KEYDOWN(100305) OR _KEYDOWN(100306) THEN
        editor.CursorY = 1
        editor.CursorX = 0
        editor.ScrollY = 1
        editor.ScrollX = 0
      ELSE
        editor.CursorY = editor.CursorY - 28
        IF editor.CursorY < 1 THEN editor.CursorY = 1
        IF editor.CursorX > LEN(editorText$(editor.CursorY)) THEN editor.CursorX = LEN(editorText$(editor.CursorY))
      END IF
    END IF

    IF kVal = 20736 THEN ' Page down
      IF _KEYDOWN(100305) OR _KEYDOWN(100306) THEN
        editor.CursorY = lastLine
        editor.CursorX = LEN(editorText$(editor.CursorY))
        editor.ScrollY = lastLine - 27
        IF editor.ScrollY < 1 THEN editor.ScrollY = 1
      ELSE
        editor.CursorY = editor.CursorY + 28
        IF editor.CursorY > lastLine THEN editor.CursorY = lastLine
        IF editor.CursorX > LEN(editorText$(editor.CursorY)) THEN editor.CursorX = LEN(editorText$(editor.CursorY))
      END IF
    END IF

    IF editor.CursorY < editor.ScrollY THEN editor.ScrollY = editor.CursorY
    IF editor.CursorY >= editor.ScrollY + 28 THEN editor.ScrollY = editor.CursorY - 27

    IF editor.CursorX < editor.ScrollX THEN editor.ScrollX = editor.CursorX
    IF editor.CursorX >= editor.ScrollX + 56 THEN editor.ScrollX = editor.CursorX - 55

    IF oldCursorY <> editor.CursorY THEN refineCode (0)

  END IF

END SUB ' processInput

''''''''''''''''''''''''
FUNCTION processVScrollbar (wPosX, wPosY, wSizeX, wSizeY, wTotalItems, wMaxVis, passCurScroll, passDragActive, passDragOffset, wIs1Based)

  returnExtraPrepare

  drawBorderBox wPosX, wPosY, wSizeX, wSizeY, 15, 0

  charX = wPosX + (wSizeX \ 2) - 4
  PrintChr charX, wPosY + 2, CHR$(24), 15, 0, 1
  PrintChr charX, wPosY + wSizeY - 9, CHR$(25), 15, 0, 1

  minScroll = 0
  IF wIs1Based = 1 THEN minScroll = 1

  scrollRange = wTotalItems - wMaxVis
  IF scrollRange < 0 THEN scrollRange = 0

  maxScroll = scrollRange + minScroll

  thumbMaxH = wSizeY - 20
  IF wTotalItems > wMaxVis THEN
    thumbSize = (wMaxVis * thumbMaxH) \ wTotalItems
    IF thumbSize < 8 THEN thumbSize = 8
    IF scrollRange > 0 THEN
      thumbY = wPosY + 10 + (((passCurScroll - minScroll) * (thumbMaxH - thumbSize)) \ scrollRange)
    ELSE
      thumbY = wPosY + 10
    END IF
    LINE (wPosX + 1, thumbY)-(wPosX + wSizeX - 2, thumbY + thumbSize - 1), 15, BF
  ELSE
    thumbSize = thumbMaxH
    thumbY = wPosY + 10
    LINE (wPosX + 1, thumbY)-(wPosX + wSizeX - 2, thumbY + thumbSize - 1), 15, BF
  END IF

  ' Mouse Logic
  IF mouse.Clicked1 THEN
    IF wTotalItems > wMaxVis THEN
      IF mouseWithinBoxBounds(wPosX, thumbY, wSizeX, thumbSize) THEN
        passDragActive = 1
        passDragOffset = mouse.PosY - thumbY
      ELSE
        IF mouseWithinBoxBounds(wPosX, wPosY + 10, wSizeX, thumbMaxH) THEN
          IF mouse.PosY < thumbY THEN
            passCurScroll = passCurScroll - wMaxVis
            IF passCurScroll < minScroll THEN passCurScroll = minScroll
          ELSE
            passCurScroll = passCurScroll + wMaxVis
            IF passCurScroll > maxScroll THEN passCurScroll = maxScroll
          END IF
        END IF
      END IF
    END IF

    IF mouseWithinBoxBounds(wPosX, wPosY, wSizeX, 10) THEN
      passCurScroll = passCurScroll - 1
      IF passCurScroll < minScroll THEN passCurScroll = minScroll
    END IF

    IF mouseWithinBoxBounds(wPosX, wPosY + wSizeY - 10, wSizeX, 10) THEN
      passCurScroll = passCurScroll + 1
      IF passCurScroll > maxScroll THEN passCurScroll = maxScroll
    END IF
  END IF

  IF mouse.Button1Down AND passDragActive = 1 THEN
    IF wTotalItems > wMaxVis THEN
      newThumbY = mouse.PosY - passDragOffset
      trackSize = thumbMaxH - thumbSize
      IF trackSize > 0 THEN
        newScroll = minScroll + (((newThumbY - (wPosY + 10)) * scrollRange) \ trackSize)
        IF newScroll < minScroll THEN newScroll = minScroll
        IF newScroll > maxScroll THEN newScroll = maxScroll
        passCurScroll = newScroll
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    passDragActive = 0
  END IF

  return3 passDragOffset
  return2 passDragActive
  processVScrollbar = passCurScroll

END FUNCTION ' processVScrollbar

''''''''''''''''''''''''
SUB pushStatusMsg (wStr$)

  IF statusMsgCount < 1000 THEN
    statusMsg$(statusMsgCount) = wStr$
    statusMsgCount = statusMsgCount + 1
  ELSE
    FOR ii = 1 TO 998
      statusMsg$(ii) = statusMsg$(ii + 1)
    NEXT
    statusMsg$(999) = wStr$
  END IF

  statusBoxH = 38
  maxLines = (statusBoxH - 8) \ 10
  IF (statusMsgCount - 1) > maxLines THEN
    editor.StatusScrollY = statusMsgCount - maxLines
  ELSE
    editor.StatusScrollY = 1
  END IF

END SUB ' pushStatusMsg

''''''''''''''''''''''''
SUB redrawAll

  CLS
  COLOR 15

  editor.MenuClicked = 0

  drawEditorPMI
  drawStatusPMI
  drawButtonsPMI
  drawTopMenuAndScrollPMI
  drawFuncListPMI
  drawCornerPMI

  IF mouse.Released1 THEN
    IF editor.MenuClicked = 0 THEN
      editor.TopMenuFocus = 0
    END IF
  END IF

  ' Print text cursor and mouse position information at the lower right
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 48, "MSX:" + cTrNum$(mouse.PosX), 15, 0, 1
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 36, "MSY:" + cTrNum$(mouse.PosY), 15, 0, 1
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 24, "CX:" + cTrNum$(editor.CursorX), 15, 0, 1
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 12, "CY:" + cTrNum$(editor.CursorY), 15, 0, 1

  displayFlashText

END SUB ' redrawAll

''''''''''''''''''''''''
SUB refineCode (isCompileClick)

  DIM refName$(MAX_SYMBOLS)
  DIM refScope(MAX_SYMBOLS) AS LONG
  DIM activeScope AS LONG
  DIM scopeCounter AS LONG

  ' String Tracking State for Enforcing/Stripping '$' Suffix in Standard Mode
  DIM strDeclName$(1024)
  DIM strDeclScope(1024) AS LONG
  DIM strDeclType(1024) AS LONG ' 0 = Suspended, 1 = Requires $ (Dynamic/Fixed with $), 2 = Requires NO $ (Fixed without $)

  DIM isStrFound AS LONG
  DIM foundStrIdx AS LONG
  DIM isVarFound AS LONG
  DIM foundVarIdx AS LONG
  DIM hasPendingStr AS LONG

  strDeclCount = 0

  refCount = 0
  activeScope = 0
  scopeCounter = 0

  uiSubCount = 0

  ' Quick prescan for #CLASSIC and #STRINGSTRICT to ensure the editor accurately respects duck typing and string rules during refinement.
  ' Pre-evaluating these directives is required because refinement occurs prior to the main scan pass
  compileClassicMode = 0
  compileStringStrict = 0
  compileEmeraldMode = 0
  FOR iy = 1 TO editor.LastLine
    tempScan$ = UCASE$(LTRIM$(RTRIM$(editorText$(iy))))
    IF LEFT$(tempScan$, 1) = "'" THEN tempScan$ = LTRIM$(MID$(tempScan$, 2))
    IF LEFT$(tempScan$, 8) = "#CLASSIC" THEN compileClassicMode = 1
    IF LEFT$(tempScan$, 13) = "#STRINGSTRICT" THEN compileStringStrict = 1
    IF LEFT$(tempScan$, 8) = "#EMERALD" THEN
      compileEmeraldMode = 1
      compileStringStrict = 1
    END IF
  NEXT

  IF editor.HasCustomPalette = 1 THEN
    ' Palette is active
    IF compileClassicMode = 1 THEN
      sysColor.focusBorder = 10
    ELSE
      sysColor.focusBorder = 10
    END IF
  ELSE
    ' Standard palette
    IF compileClassicMode = 1 THEN
      sysColor.focusBorder = 9
    ELSE
      sysColor.focusBorder = 10
    END IF
  END IF

  FOR iy = 1 TO editor.LastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    curLine$ = editorText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    uTemp$ = UCASE$(tempLine$)
    IF LEFT$(uTemp$, 4) = "SUB " OR LEFT$(uTemp$, 9) = "FUNCTION " THEN
      scopeCounter = scopeCounter + 1
      activeScope = scopeCounter
    END IF

    IF LEN(tempLine$) > 0 THEN
      newLine$ = ""
      ix = 1
      lineLen = LEN(curLine$)
      hasNonSpace = 0
      lastKwVal = 0

      ' State Machine per line for detecting AS DSTRING and AS STRING *
      asMode = 0
      lastVarBase$ = ""
      lastVarSuffix$ = ""
      pendingStrIdx = 0
      hasPendingStr = 0
      parenDepth = 0

      isValidLine = 0
      IF INSTR(curLine$, "=") > 0 THEN isValidLine = 1
      firstIdent$ = ""
      FOR i_scan = 1 TO lineLen
        c_scan$ = MID$(curLine$, i_scan, 1)
        IF (c_scan$ >= "A" AND c_scan$ <= "Z") OR (c_scan$ >= "a" AND c_scan$ <= "z") OR c_scan$ = "_" THEN
          FOR j_scan = i_scan TO lineLen
            c2_scan$ = MID$(curLine$, j_scan, 1)
            u2_scan$ = UCASE$(c2_scan$)
            IF (u2_scan$ >= "A" AND u2_scan$ <= "Z") OR (u2_scan$ >= "0" AND u2_scan$ <= "9") OR c2_scan$ = "_" THEN
              firstIdent$ = firstIdent$ + c2_scan$
            ELSE
              EXIT FOR
            END IF
          NEXT
          EXIT FOR
        END IF
      NEXT
      IF firstIdent$ <> "" THEN
        uFirst$ = UCASE$(firstIdent$)

        uIdentSearch$ = uFirst$
        IF uIdentSearch$ = "_BYTE" THEN uIdentSearch$ = "BYTE"
        IF uIdentSearch$ = "_INTEGER" THEN uIdentSearch$ = "INTEGER"
        IF uIdentSearch$ = "_LONG" THEN uIdentSearch$ = "LONG"
        IF uIdentSearch$ = "_INTEGER64" THEN uIdentSearch$ = "INTEGER64"
        IF uIdentSearch$ = "_SINGLE" THEN uIdentSearch$ = "SINGLE"
        IF uIdentSearch$ = "_DOUBLE" THEN uIdentSearch$ = "DOUBLE"
        IF uIdentSearch$ = "_STRING" THEN uIdentSearch$ = "STRING"
        IF uIdentSearch$ = "_DSTRING" THEN uIdentSearch$ = "DSTRING"
        IF uIdentSearch$ = "_UNSIGNED" THEN uIdentSearch$ = "UNSIGNED"
        IF uIdentSearch$ = "_ANY" THEN uIdentSearch$ = "ANY"

        FOR ii = 512 TO 1023
          IF voc(ii).text <> "" THEN
            IF uIdentSearch$ = voc(ii).text THEN
              isValidLine = 1
              EXIT FOR
            END IF
          END IF
        NEXT
      END IF

      DO WHILE ix <= lineLen
        ch$ = MID$(curLine$, ix, 1)

        IF ch$ = " " OR ch$ = CHR$(9) THEN
          IF hasNonSpace = 0 THEN
            newLine$ = newLine$ + ch$
            ix = ix + 1
          ELSE
            newLine$ = newLine$ + " "
            ix = ix + 1
            DO WHILE ix <= lineLen
              ch2$ = MID$(curLine$, ix, 1)
              IF ch2$ = " " OR ch2$ = CHR$(9) THEN
                ix = ix + 1
              ELSE
                EXIT DO
              END IF
            LOOP
          END IF
        ELSE
          hasNonSpace = 1

          IF ch$ = "'" THEN
            newLine$ = newLine$ + MID$(curLine$, ix)
            EXIT DO
          END IF

          IF ch$ = CHR$(34) THEN
            newLine$ = newLine$ + ch$
            ix = ix + 1
            DO WHILE ix <= lineLen
              ch2$ = MID$(curLine$, ix, 1)
              newLine$ = newLine$ + ch2$
              ix = ix + 1
              IF ch2$ = CHR$(34) THEN EXIT DO
            LOOP
            lastKwVal = 0
          ELSE
            IF (ch$ >= "A" AND ch$ <= "Z") OR (ch$ >= "a" AND ch$ <= "z") OR ch$ = "_" THEN
              ident$ = ""
              DO WHILE ix <= lineLen
                ch2$ = MID$(curLine$, ix, 1)
                u2$ = UCASE$(ch2$)
                IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") OR ch2$ = "_" THEN
                  ident$ = ident$ + ch2$
                  ix = ix + 1
                ELSE
                  EXIT DO
                END IF
              LOOP

              suffixCh$ = ""
              IF ix <= lineLen THEN
                ch2$ = MID$(curLine$, ix, 1)
                IF ch2$ = "$" OR ch2$ = "#" OR ch2$ = "!" OR ch2$ = "&" OR ch2$ = "%" THEN
                  suffixCh$ = ch2$
                  ident$ = ident$ + ch2$
                  ix = ix + 1
                END IF
              END IF

              ' Lookahead specifically for AS DSTRING to aggressively append the suffix
              IF compileClassicMode = 0 AND suffixCh$ = "" AND parenDepth = 0 THEN
                lookIx = ix
                lookPDepth = 0
                DO WHILE lookIx <= lineLen
                  lCh$ = MID$(curLine$, lookIx, 1)
                  IF lCh$ = "(" THEN lookPDepth = lookPDepth + 1
                  IF lCh$ = ")" THEN lookPDepth = lookPDepth - 1
                  IF lookPDepth = 0 AND lCh$ <> ")" AND lCh$ <> "(" AND lCh$ <> " " AND lCh$ <> CHR$(9) THEN EXIT DO
                  lookIx = lookIx + 1
                LOOP
                IF UCASE$(MID$(curLine$, lookIx, 2)) = "AS" THEN
                  lookIx = lookIx + 2
                  lCh$ = MID$(curLine$, lookIx, 1)
                  IF lCh$ = " " OR lCh$ = CHR$(9) THEN
                    DO WHILE lookIx <= lineLen
                      lCh$ = MID$(curLine$, lookIx, 1)
                      IF lCh$ = " " OR lCh$ = CHR$(9) THEN lookIx = lookIx + 1 ELSE EXIT DO
                    LOOP
                    IF UCASE$(MID$(curLine$, lookIx, 7)) = "DSTRING" THEN
                      lChNext$ = MID$(curLine$, lookIx + 7, 1)
                      uNext$ = UCASE$(lChNext$)
                      IF NOT ((uNext$ >= "A" AND uNext$ <= "Z") OR (uNext$ >= "0" AND uNext$ <= "9") OR uNext$ = "_") THEN
                        ident$ = ident$ + "$"
                        suffixCh$ = "$"
                      END IF
                    END IF
                  END IF
                END IF
              END IF

              uIdent$ = UCASE$(ident$)

              uIdentSearch$ = uIdent$
              IF uIdentSearch$ = "_BYTE" THEN uIdentSearch$ = "BYTE"
              IF uIdentSearch$ = "_INTEGER" THEN uIdentSearch$ = "INTEGER"
              IF uIdentSearch$ = "_LONG" THEN uIdentSearch$ = "LONG"
              IF uIdentSearch$ = "_INTEGER64" THEN uIdentSearch$ = "INTEGER64"
              IF uIdentSearch$ = "_SINGLE" THEN uIdentSearch$ = "SINGLE"
              IF uIdentSearch$ = "_DOUBLE" THEN uIdentSearch$ = "DOUBLE"
              IF uIdentSearch$ = "_STRING" THEN uIdentSearch$ = "STRING"
              IF uIdentSearch$ = "_DSTRING" THEN uIdentSearch$ = "DSTRING"
              IF uIdentSearch$ = "_UNSIGNED" THEN uIdentSearch$ = "UNSIGNED"
              IF uIdentSearch$ = "_ANY" THEN uIdentSearch$ = "ANY"

              isKey = 0
              kwVal = 0
              FOR ii = 512 TO 1023
                IF voc(ii).text <> "" THEN
                  IF uIdentSearch$ = voc(ii).text THEN
                    isKey = 1
                    kwVal = ii
                    EXIT FOR
                  END IF
                END IF
              NEXT

              IF isKey = 1 THEN
                newLine$ = newLine$ + uIdent$
                lastKwVal = kwVal

                ' AS STRING / AS DSTRING detection state machine
                SELECT CASE kwVal

                  CASE TOK_AS
                    asMode = 1
                    IF lastVarBase$ <> "" THEN
                      isStrFound = 0
                      foundStrIdx = 0
                      FOR iStr = 0 TO strDeclCount - 1
                        IF strDeclName$(iStr) = lastVarBase$ AND strDeclScope(iStr) = activeScope THEN
                          foundStrIdx = iStr
                          isStrFound = 1
                          EXIT FOR
                        END IF
                      NEXT
                      IF isStrFound = 0 AND strDeclCount < 1024 THEN
                        foundStrIdx = strDeclCount
                        strDeclName$(foundStrIdx) = lastVarBase$
                        strDeclScope(foundStrIdx) = activeScope
                        strDeclCount = strDeclCount + 1
                        isStrFound = 1
                      END IF
                      IF isStrFound = 1 THEN
                        strDeclType(foundStrIdx) = 0 ' Suspend initially
                        pendingStrIdx = foundStrIdx
                        hasPendingStr = 1
                      END IF
                    END IF

                  CASE TOK_DSTRING
                    IF asMode = 1 THEN
                      asMode = 0
                      IF hasPendingStr = 1 THEN
                        strDeclType(pendingStrIdx) = 1 ' DSTRING forces $
                        hasPendingStr = 0
                      END IF
                    ELSE
                      asMode = 0
                      hasPendingStr = 0
                    END IF

                  CASE TOK_STRING
                    IF asMode = 1 THEN
                      IF compileStringStrict = 1 THEN
                        asMode = 3 ' Waiting for *
                      ELSE
                        asMode = 5 ' Optional *
                      END IF
                    ELSE
                      asMode = 0
                      hasPendingStr = 0
                    END IF

                  CASE ELSE
                    asMode = 0
                    hasPendingStr = 0

                END SELECT ' kwVal

              ELSE
                ' Is Variable / Label / Sub Call
                IF lastKwVal = TOK_DEF THEN
                  IF UCASE$(LEFT$(ident$, 2)) = "FN" THEN
                    IF LEN(ident$) = 2 THEN
                      ident$ = "FN"
                    ELSE
                      ident$ = "Fn" + MID$(ident$, 3)
                    END IF
                  END IF
                END IF
                lastKwVal = 0

                SELECT CASE asMode

                  CASE 4
                    ' Valid identifier used as length (e.g. constant)
                    asMode = 0
                    IF hasPendingStr = 1 THEN
                      IF lastVarSuffix$ = "$" THEN
                        strDeclType(pendingStrIdx) = 1
                      ELSE
                        strDeclType(pendingStrIdx) = 2
                      END IF
                      hasPendingStr = 0
                    END IF

                  CASE 5
                    ' We saw AS STRING, but no *, and now we hit a variable. It's a dynamic string
                    asMode = 0
                    IF hasPendingStr = 1 THEN
                      IF lastVarSuffix$ = "$" THEN
                        strDeclType(pendingStrIdx) = 1
                      ELSE
                        strDeclType(pendingStrIdx) = 2
                      END IF
                      hasPendingStr = 0
                    END IF

                  CASE ELSE
                    asMode = 0
                    hasPendingStr = 0

                END SELECT ' asMode

                baseName$ = UCASE$(ident$)
                IF suffixCh$ <> "" THEN baseName$ = LEFT$(baseName$, LEN(baseName$) - 1)

                ' Only track variables for string typing if they aren't enclosed in parentheses (e.g. array dimensions)
                IF parenDepth = 0 THEN
                  lastVarBase$ = baseName$
                  lastVarSuffix$ = suffixCh$
                END IF

                ' Register implicit strings (those typed with a $ suffix) so they are tracked just like explicit AS STRING declarations.
                ' This happens on both typing and compile passes unless #CLASSIC mode is active.
                IF compileClassicMode = 0 AND suffixCh$ = "$" THEN
                  isStrFound = 0
                  foundStrIdx = 0
                  FOR iStr = 0 TO strDeclCount - 1
                    IF strDeclName$(iStr) = baseName$ AND strDeclScope(iStr) = activeScope THEN
                      foundStrIdx = iStr
                      isStrFound = 1
                      EXIT FOR
                    END IF
                  NEXT
                  IF isStrFound = 0 AND strDeclCount < 1024 THEN
                    foundStrIdx = strDeclCount
                    strDeclName$(foundStrIdx) = baseName$
                    strDeclScope(foundStrIdx) = activeScope
                    strDeclType(foundStrIdx) = 1 ' Mark as Requires $
                    strDeclCount = strDeclCount + 1
                  END IF
                END IF

                strType = 0
                IF compileClassicMode = 0 THEN
                  ' Look up string tracking table
                  FOR iStr = 0 TO strDeclCount - 1
                    IF strDeclName$(iStr) = baseName$ THEN
                      IF strDeclScope(iStr) = activeScope OR strDeclScope(iStr) = 0 THEN
                        strType = strDeclType(iStr)
                        EXIT FOR
                      END IF
                    END IF
                  NEXT
                END IF

                ' Suffix formatting for Standard Mode
                IF compileClassicMode = 0 THEN

                  SELECT CASE strType

                    CASE 1 ' Requires $: Force $
                      IF suffixCh$ <> "$" THEN
                        ident$ = ident$ + "$"
                        suffixCh$ = "$"
                      END IF
                    CASE 2 ' Requires no $: Force no $
                      IF suffixCh$ = "$" THEN
                        ident$ = LEFT$(ident$, LEN(ident$) - 1)
                        suffixCh$ = ""
                      END IF
                    CASE ELSE ' Numeric, Undeclared, or Suspended
                      ' Only aggressive suffix stripping on compile clicks for non-strings!
                      IF isCompileClick = 1 THEN
                        IF suffixCh$ = "#" OR suffixCh$ = "!" OR suffixCh$ = "&" OR suffixCh$ = "%" THEN
                          ident$ = LEFT$(ident$, LEN(ident$) - 1)
                          suffixCh$ = ""
                        END IF
                      END IF

                  END SELECT ' strType

                END IF

                isVarFound = 0
                foundVarIdx = 0
                uIdent$ = UCASE$(ident$)

                FOR ii = 0 TO refCount - 1
                  IF UCASE$(refName$(ii)) = uIdent$ THEN
                    IF refScope(ii) = activeScope THEN
                      foundVarIdx = ii
                      isVarFound = 1
                      EXIT FOR
                    END IF
                  END IF
                NEXT

                IF isVarFound = 0 AND activeScope > 0 THEN
                  FOR ii = 0 TO refCount - 1
                    IF UCASE$(refName$(ii)) = uIdent$ THEN
                      IF refScope(ii) = 0 THEN
                        foundVarIdx = ii
                        isVarFound = 1
                        EXIT FOR
                      END IF
                    END IF
                  NEXT
                END IF

                IF isValidLine = 1 THEN
                  IF isVarFound = 0 THEN
                    IF refCount < MAX_SYMBOLS THEN
                      foundVarIdx = refCount
                      refName$(foundVarIdx) = ident$
                      refScope(foundVarIdx) = activeScope
                      refCount = refCount + 1
                    END IF
                    newLine$ = newLine$ + ident$
                  ELSE
                    newLine$ = newLine$ + refName$(foundVarIdx)
                  END IF
                ELSE
                  IF isVarFound = 0 THEN
                    newLine$ = newLine$ + ident$
                  ELSE
                    newLine$ = newLine$ + refName$(foundVarIdx)
                  END IF
                END IF
              END IF
            ELSE
              ' Symbol
              newLine$ = newLine$ + ch$
              ix = ix + 1
              lastKwVal = 0

              IF ch$ = "(" THEN parenDepth = parenDepth + 1
              IF ch$ = ")" THEN parenDepth = parenDepth - 1

              IF ch$ = "*" AND (asMode = 3 OR asMode = 5) THEN
                asMode = 4 ' Waiting for length
              ELSE
                IF ch$ <> " " AND ch$ <> CHR$(9) THEN
                  IF asMode = 4 THEN
                    ' If we see a valid number, we successfully found our length
                    IF ch$ >= "0" AND ch$ <= "9" THEN
                      asMode = 0
                      IF hasPendingStr = 1 THEN
                        IF lastVarSuffix$ = "$" THEN
                          strDeclType(pendingStrIdx) = 1
                        ELSE
                          strDeclType(pendingStrIdx) = 2
                        END IF
                        hasPendingStr = 0
                      END IF
                    ELSE
                      ' Garbage found! Abort commit and leave the variable Suspended
                      asMode = 0
                      hasPendingStr = 0
                    END IF
                  ELSE
                    IF asMode = 5 THEN
                      ' Hit a non-space symbol right after AS STRING. Treat as dynamic.
                      asMode = 0
                      IF hasPendingStr = 1 THEN
                        IF lastVarSuffix$ = "$" THEN
                          strDeclType(pendingStrIdx) = 1
                        ELSE
                          strDeclType(pendingStrIdx) = 2
                        END IF
                        hasPendingStr = 0
                      END IF
                    ELSE
                      asMode = 0
                      hasPendingStr = 0
                    END IF
                  END IF
                END IF
              END IF
            END IF
          END IF
        END IF
      LOOP

      editorText$(iy) = RTRIM$(newLine$)

      testSub$ = LTRIM$(editorText$(iy))
      IF LEFT$(testSub$, 4) = "SUB " OR LEFT$(testSub$, 9) = "FUNCTION " THEN
        IF uiSubCount < MAX_UI_SUBS THEN
          IF LEFT$(testSub$, 4) = "SUB " THEN
            sName$ = LTRIM$(RTRIM$(MID$(testSub$, 5)))
          ELSE
            sName$ = LTRIM$(RTRIM$(MID$(testSub$, 10)))
          END IF
          parenPos = INSTR(sName$, "(")
          IF parenPos > 0 THEN sName$ = RTRIM$(LEFT$(sName$, parenPos - 1))
          uiSubName$(uiSubCount) = sName$
          uiSubLine(uiSubCount) = iy
          uiSubCount = uiSubCount + 1
        END IF
      END IF

    ELSE
      editorText$(iy) = ""
    END IF

    IF LEFT$(uTemp$, 8) = "END SUB" OR LEFT$(uTemp$, 12) = "END FUNCTION" THEN
      activeScope = 0
    END IF
  NEXT

END SUB ' refineCode

''''''''''''''''''''''''
FUNCTION resolveSymbol (vName$)

  returnExtraPrepare

  DIM dType AS LONG
  DIM vIdx AS LONG
  DIM isExp AS LONG
  DIM charIdx AS LONG
  DIM hVal AS LONG
  DIM conflictIdx AS LONG

  searchName$ = UCASE$(vName$)

  ' Safety net: If a parser loophole leaked a blank identifier, reject it immediately
  ' This prevents ASC crashes and stops ghost symbols from entering the symbol table
  IF searchName$ = "" THEN
    throwCompilerError "EXPECTED IDENTIFIER", ASIS, 0
    EXIT FUNCTION
  END IF

  ' Enforcement check to prevent internal variables from using legacy type suffixes
  firstChar$ = LEFT$(searchName$, 1)
  IF firstChar$ = "!" OR firstChar$ = "~" THEN
    lastChar$ = RIGHT$(searchName$, 1)
    IF lastChar$ = "#" OR lastChar$ = "!" OR lastChar$ = "%" OR lastChar$ = "&" THEN
      ESCAPETEXT2 "FATAL in resolveSymbol", "Internal variable " + searchName$ + " cannot use legacy type suffix '" + lastChar$ + "'."
    END IF
  END IF

  IF findSymbol(searchName$) THEN
    vIdx = returnedData2
    return3 symbols(vIdx).DataType
    return2 vIdx
    resolveSymbol = 1
    EXIT FUNCTION
  END IF

  dType = TYPE_SINGLE
  isExp = 0

  firstChar$ = LEFT$(searchName$, 1)
  IF firstChar$ = "!" OR firstChar$ = "~" THEN
    dType = TYPE_INTEGER64
    isExp = 1
  ELSE
    IF firstChar$ = "%" OR firstChar$ = "@" THEN
      dType = TYPE_LABEL
      isExp = 1
    ELSE
      charIdx = ASC(firstChar$) - 65
      IF charIdx >= 0 AND charIdx <= 25 THEN
        IF defIntMap(charIdx) = 1 THEN dType = TYPE_INTEGER
      END IF
    END IF
  END IF

  suffix$ = RIGHT$(searchName$, 1)
  SELECT CASE suffix$

    CASE "$"
      dType = TYPE_STRING

    CASE "#"
      dType = TYPE_DOUBLE

    CASE "!"
      dType = TYPE_SINGLE

    CASE "&"
      dType = TYPE_LONG

    CASE "%"
      dType = TYPE_INTEGER

    CASE ELSE
      suffix$ = ""
      IF expectedSymType <> TYPE_ANY AND isExp = 0 THEN
        dType = expectedSymType
      END IF

  END SELECT ' suffix$

  IF compileClassicMode = 1 THEN
    IF suffix$ = "$" THEN
      IF findSymbol(LEFT$(searchName$, LEN(searchName$) - 1)) THEN
        conflictIdx = returnedData2
        IF symbols(conflictIdx).DataType <> TYPE_STRING THEN
          throwCompilerError "STRING NAME CONFLICT", ASIS, 0
          EXIT FUNCTION
        END IF
      END IF
    ELSE
      IF findSymbol(searchName$ + "$") THEN
        conflictIdx = returnedData2
        throwCompilerError "STRING NAME CONFLICT", ASIS, 0
        EXIT FUNCTION
      END IF
    END IF
  END IF

  IF symbolCount >= MAX_SYMBOLS THEN
    throwCompilerError "SYMBOL LIMIT", ASIS, 0
    EXIT FUNCTION
  END IF

  vIdx = symbolCount
  symbols(vIdx).RecordName = searchName$
  symbols(vIdx).DataType = dType
  symbols(vIdx).ScopeID = currentScopeID
  symbols(vIdx).IsShared = 0
  symbols(vIdx).IsArray = 0
  symbols(vIdx).Size = 1
  symbols(vIdx).Size2 = 0
  symbols(vIdx).Offset = 0
  symbols(vIdx).SubIndex = 0
  symbols(vIdx).UDTIndex = -1
  symbols(vIdx).IsExplicit = isExp
  symbols(vIdx).alreadyParsed = 0

  symbols(vIdx).IsLocal = LOCAL_GLOBAL

  IF currentScopeID > 0 AND firstChar$ <> "!" AND firstChar$ <> "%" AND firstChar$ <> "@" THEN
    symbols(vIdx).IsLocal = LOCAL_STANDARD
  END IF

  symbols(vIdx).LocalOffset = 0
  symbols(vIdx).DescOffset = 0
  symbols(vIdx).StrOffset = 0
  symbols(vIdx).FixedStrLen = 0

  hVal = hashString(searchName$)
  symbols(vIdx).HashNext = symHash(hVal)
  symHash(hVal) = vIdx

  symbolCount = symbolCount + 1

  return3 dType
  return2 vIdx
  resolveSymbol = 1

END FUNCTION ' resolveSymbol

''''''''''''''''''''''''
FUNCTION retCoordinateBoundaries (passStartIdx, passEndIdx)

  returnExtraPrepare

  DIM tempStart AS LONG
  DIM tempEnd AS LONG
  DIM cPos AS LONG

  tempStart = passStartIdx
  tempEnd = passEndIdx

  ' Strip surrounding parentheses if they exist to isolate the coordinate arguments
  IF lineTokenVals(tempStart) = 256 + ASC("(") THEN
    IF lineTokenVals(tempEnd) = 256 + ASC(")") THEN
      tempStart = tempStart + 1
      tempEnd = tempEnd - 1
    END IF
  END IF

  cPos = findComma(tempStart, tempEnd)

  return3 tempEnd
  return2 tempStart

  retCoordinateBoundaries = cPos

END FUNCTION ' retCoordinateBoundaries

''''''''''''''''''''''''
FUNCTION retEditorSelection$

  IF editor.SelectStartY < editor.CursorY OR (editor.SelectStartY = editor.CursorY AND editor.SelectStartX < editor.CursorX) THEN
    startY = editor.SelectStartY
    startX = editor.SelectStartX
    endY = editor.CursorY
    endX = editor.CursorX
  ELSE
    startY = editor.CursorY
    startX = editor.CursorX
    endY = editor.SelectStartY
    endX = editor.SelectStartX
  END IF

  IF startY = endY AND startX = endX THEN
    retEditorSelection$ = editorText$(editor.CursorY)
    EXIT FUNCTION
  END IF

  outStr$ = ""
  FOR iy = startY TO endY
    curLine$ = editorText$(iy)
    IF startY = endY THEN
      outStr$ = MID$(curLine$, startX + 1, endX - startX)
    ELSE
      IF iy = startY THEN
        outStr$ = outStr$ + MID$(curLine$, startX + 1) + CHR$(13) + CHR$(10)
      ELSE
        IF iy = endY THEN
          outStr$ = outStr$ + LEFT$(curLine$, endX)
        ELSE
          outStr$ = outStr$ + curLine$ + CHR$(13) + CHR$(10)
        END IF
      END IF
    END IF
  NEXT

  retEditorSelection$ = outStr$

END FUNCTION ' retEditorSelection$

''''''''''''''''''''''''
FUNCTION retFixedStringLength (vIdx)

  retFixedStringLength = symbols(vIdx).FixedStrLen

END FUNCTION ' retFixedStringLength

''''''''''''''''''''''''
FUNCTION retIatConstByName (wName$, isTira)

  tempRet = IAT_INVALID

  IF isTira = 1 THEN
    SELECT CASE wName$

      CASE "IAT_GETSTDHANDLE": tempRet = IAT_GETSTDHANDLE
      CASE "IAT_WRITEFILE": tempRet = IAT_WRITEFILE
      CASE "IAT_READFILE": tempRet = IAT_READFILE
      CASE "IAT_EXITPROCESS": tempRet = IAT_EXITPROCESS
      CASE "IAT_GETMODULEHANDLEA": tempRet = IAT_GETMODULEHANDLEA
      CASE "IAT_SETCONSOLEMODE": tempRet = IAT_SETCONSOLEMODE
      CASE "IAT_DEFWINDOWPROCA": tempRet = IAT_DEFWINDOWPROCA
      CASE "IAT_REGISTERCLASSEXA": tempRet = IAT_REGISTERCLASSEXA
      CASE "IAT_CREATEWINDOWEXA": tempRet = IAT_CREATEWINDOWEXA
      CASE "IAT_SHOWWINDOW": tempRet = IAT_SHOWWINDOW
      CASE "IAT_PEEKMESSAGEA": tempRet = IAT_PEEKMESSAGEA
      CASE "IAT_TRANSLATEMESSAGE": tempRet = IAT_TRANSLATEMESSAGE
      CASE "IAT_DISPATCHMESSAGEA": tempRet = IAT_DISPATCHMESSAGEA
      CASE "IAT_POSTQUITMESSAGE": tempRet = IAT_POSTQUITMESSAGE
      CASE "IAT_ADDVECTOREDEXCEPTIONHANDLER": tempRet = IAT_ADDVECTOREDEXCEPTIONHANDLER
      CASE "IAT_ADJUSTWINDOWRECTEX": tempRet = IAT_ADJUSTWINDOWRECTEX
      CASE "IAT_ATAN": tempRet = IAT_ATAN
      CASE "IAT_BEEP": tempRet = IAT_BEEP
      CASE "IAT_BEGINPAINT": tempRet = IAT_BEGINPAINT
      CASE "IAT_BITBLT": tempRet = IAT_BITBLT
      CASE "IAT_CLOSEHANDLE": tempRet = IAT_CLOSEHANDLE
      CASE "IAT_COS": tempRet = IAT_COS
      CASE "IAT_CREATECOMPATIBLEBITMAP": tempRet = IAT_CREATECOMPATIBLEBITMAP
      CASE "IAT_CREATECOMPATIBLEDC": tempRet = IAT_CREATECOMPATIBLEDC
      CASE "IAT_CREATEDIBSECTION": tempRet = IAT_CREATEDIBSECTION
      CASE "IAT_CREATEFILEA": tempRet = IAT_CREATEFILEA
      CASE "IAT_CREATEFONTA": tempRet = IAT_CREATEFONTA
      CASE "IAT_CREATETHREAD": tempRet = IAT_CREATETHREAD
      CASE "IAT_DELETEDC": tempRet = IAT_DELETEDC
      CASE "IAT_DELETEFILEA": tempRet = IAT_DELETEFILEA
      CASE "IAT_DELETEOBJECT": tempRet = IAT_DELETEOBJECT
      CASE "IAT_DWMSETWINDOWATTRIBUTE": tempRet = IAT_DWMSETWINDOWATTRIBUTE
      CASE "IAT_ENDPAINT": tempRet = IAT_ENDPAINT
      CASE "IAT_EXITTHREAD": tempRet = IAT_EXITTHREAD
      CASE "IAT_GETASYNCKEYSTATE": tempRet = IAT_GETASYNCKEYSTATE
      CASE "IAT_GETFILESIZE": tempRet = IAT_GETFILESIZE
      CASE "IAT_GETPROCESSHEAP": tempRet = IAT_GETPROCESSHEAP
      CASE "IAT_GETSTOCKOBJECT": tempRet = IAT_GETSTOCKOBJECT
      CASE "IAT_GETSYSTEMMETRICS": tempRet = IAT_GETSYSTEMMETRICS
      CASE "IAT_GETTICKCOUNT": tempRet = IAT_GETTICKCOUNT
      CASE "IAT_HEAPALLOC": tempRet = IAT_HEAPALLOC
      CASE "IAT_HEAPFREE": tempRet = IAT_HEAPFREE
      CASE "IAT_INVALIDATERECT": tempRet = IAT_INVALIDATERECT
      CASE "IAT_LOADCURSORA": tempRet = IAT_LOADCURSORA
      CASE "IAT_POW": tempRet = IAT_POW
      CASE "IAT_SELECTOBJECT": tempRet = IAT_SELECTOBJECT
      CASE "IAT_SETBKCOLOR": tempRet = IAT_SETBKCOLOR
      CASE "IAT_SETCONSOLECURSORPOSITION": tempRet = IAT_SETCONSOLECURSORPOSITION
      CASE "IAT_SETCONSOLETEXTATTRIBUTE": tempRet = IAT_SETCONSOLETEXTATTRIBUTE
      CASE "IAT_SETDIBCOLORTABLE": tempRet = IAT_SETDIBCOLORTABLE
      CASE "IAT_SETPIXEL": tempRet = IAT_SETPIXEL
      CASE "IAT_SETTEXTCOLOR": tempRet = IAT_SETTEXTCOLOR
      CASE "IAT_SETWINDOWLONGA": tempRet = IAT_SETWINDOWLONGA
      CASE "IAT_SETWINDOWPOS": tempRet = IAT_SETWINDOWPOS
      CASE "IAT_SIN": tempRet = IAT_SIN
      CASE "IAT_SLEEP": tempRet = IAT_SLEEP
      CASE "IAT_SPRINTF": tempRet = IAT_SPRINTF
      CASE "IAT_STRETCHBLT": tempRet = IAT_STRETCHBLT
      CASE "IAT_STRETCHDIBITS": tempRet = IAT_STRETCHDIBITS
      CASE "IAT_TEXTOUTA": tempRet = IAT_TEXTOUTA
      CASE "IAT_UPDATEWINDOW": tempRet = IAT_UPDATEWINDOW
      CASE "IAT_GETKEYSTATE": tempRet = IAT_GETKEYSTATE
      CASE "IAT_KEYBD_EVENT": tempRet = IAT_KEYBD_EVENT
      CASE "IAT_SRAND": tempRet = IAT_SRAND
      CASE "IAT_GETCURSORPOS": tempRet = IAT_GETCURSORPOS
      CASE "IAT_SCREENTOCLIENT": tempRet = IAT_SCREENTOCLIENT

    END SELECT ' wName$
  ELSE
    SELECT CASE wName$

      CASE "GetStdHandle": tempRet = IAT_GETSTDHANDLE
      CASE "WriteFile": tempRet = IAT_WRITEFILE
      CASE "ReadFile": tempRet = IAT_READFILE
      CASE "ExitProcess": tempRet = IAT_EXITPROCESS
      CASE "GetModuleHandleA": tempRet = IAT_GETMODULEHANDLEA
      CASE "SetConsoleMode": tempRet = IAT_SETCONSOLEMODE
      CASE "DefWindowProcA": tempRet = IAT_DEFWINDOWPROCA
      CASE "RegisterClassExA": tempRet = IAT_REGISTERCLASSEXA
      CASE "CreateWindowExA": tempRet = IAT_CREATEWINDOWEXA
      CASE "ShowWindow": tempRet = IAT_SHOWWINDOW
      CASE "PeekMessageA": tempRet = IAT_PEEKMESSAGEA
      CASE "TranslateMessage": tempRet = IAT_TRANSLATEMESSAGE
      CASE "DispatchMessageA": tempRet = IAT_DISPATCHMESSAGEA
      CASE "PostQuitMessage": tempRet = IAT_POSTQUITMESSAGE
      CASE "AddVectoredExceptionHandler": tempRet = IAT_ADDVECTOREDEXCEPTIONHANDLER
      CASE "AdjustWindowRectEx": tempRet = IAT_ADJUSTWINDOWRECTEX
      CASE "atan": tempRet = IAT_ATAN
      CASE "Beep": tempRet = IAT_BEEP
      CASE "BeginPaint": tempRet = IAT_BEGINPAINT
      CASE "BitBlt": tempRet = IAT_BITBLT
      CASE "cos": tempRet = IAT_COS
      CASE "CreateCompatibleBitmap": tempRet = IAT_CREATECOMPATIBLEBITMAP
      CASE "CreateCompatibleDC": tempRet = IAT_CREATECOMPATIBLEDC
      CASE "CreateDIBSection": tempRet = IAT_CREATEDIBSECTION
      CASE "CreateFileA": tempRet = IAT_CREATEFILEA
      CASE "CreateFontA": tempRet = IAT_CREATEFONTA
      CASE "CreateThread": tempRet = IAT_CREATETHREAD
      CASE "CloseHandle": tempRet = IAT_CLOSEHANDLE
      CASE "DeleteDC": tempRet = IAT_DELETEDC
      CASE "DeleteObject": tempRet = IAT_DELETEOBJECT
      CASE "DwmSetWindowAttribute": tempRet = IAT_DWMSETWINDOWATTRIBUTE
      CASE "EndPaint": tempRet = IAT_ENDPAINT
      CASE "ExitThread": tempRet = IAT_EXITTHREAD
      CASE "GetAsyncKeyState": tempRet = IAT_GETASYNCKEYSTATE
      CASE "GetFileSize": tempRet = IAT_GETFILESIZE
      CASE "GetProcessHeap": tempRet = IAT_GETPROCESSHEAP
      CASE "GetStockObject": tempRet = IAT_GETSTOCKOBJECT
      CASE "GetSystemMetrics": tempRet = IAT_GETSYSTEMMETRICS
      CASE "HeapAlloc": tempRet = IAT_HEAPALLOC
      CASE "HeapFree": tempRet = IAT_HEAPFREE
      CASE "InvalidateRect": tempRet = IAT_INVALIDATERECT
      CASE "LoadCursorA": tempRet = IAT_LOADCURSORA
      CASE "pow": tempRet = IAT_POW
      CASE "SelectObject": tempRet = IAT_SELECTOBJECT
      CASE "SetBkColor": tempRet = IAT_SETBKCOLOR
      CASE "SetConsoleCursorPosition": tempRet = IAT_SETCONSOLECURSORPOSITION
      CASE "SetConsoleTextAttribute": tempRet = IAT_SETCONSOLETEXTATTRIBUTE
      CASE "SetDIBColorTable": tempRet = IAT_SETDIBCOLORTABLE
      CASE "SetPixel": tempRet = IAT_SETPIXEL
      CASE "SetTextColor": tempRet = IAT_SETTEXTCOLOR
      CASE "SetWindowLongA": tempRet = IAT_SETWINDOWLONGA
      CASE "SetWindowPos": tempRet = IAT_SETWINDOWPOS
      CASE "sin": tempRet = IAT_SIN
      CASE "Sleep": tempRet = IAT_SLEEP
      CASE "sprintf": tempRet = IAT_SPRINTF
      CASE "StretchBlt": tempRet = IAT_STRETCHBLT
      CASE "TextOutA": tempRet = IAT_TEXTOUTA
      CASE "UpdateWindow": tempRet = IAT_UPDATEWINDOW
      CASE "DeleteFileA": tempRet = IAT_DELETEFILEA
      CASE "GetTickCount": tempRet = IAT_GETTICKCOUNT
      CASE "StretchDIBits": tempRet = IAT_STRETCHDIBITS
      CASE "GetKeyState": tempRet = IAT_GETKEYSTATE
      CASE "keybd_event": tempRet = IAT_KEYBD_EVENT
      CASE "srand": tempRet = IAT_SRAND
      CASE "GetCursorPos": tempRet = IAT_GETCURSORPOS
      CASE "ScreenToClient": tempRet = IAT_SCREENTOCLIENT

    END SELECT ' wName$
  END IF

  retIatConstByName = tempRet

END FUNCTION ' retIatConstByName

''''''''''''''''''''''''
FUNCTION retLabelStripLength$ (passLine$)

  returnExtraPrepare

  '''' Analyzes the line to find any valid label prefix and returns the string, and length via return2
  ' Used by the compile* functions

  isLabel = 0
  tempLabelStr$ = ""
  stripLen = 0

  firstChar$ = LEFT$(passLine$, 1)
  IF firstChar$ >= "0" AND firstChar$ <= "9" THEN
    FOR iCheck = 1 TO LEN(passLine$)
      chCheck$ = MID$(passLine$, iCheck, 1)
      IF chCheck$ >= "0" AND chCheck$ <= "9" THEN
        tempLabelStr$ = tempLabelStr$ + chCheck$
        stripLen = stripLen + 1
      ELSE
        EXIT FOR
      END IF
    NEXT
    isLabel = 1
    IF stripLen < LEN(passLine$) THEN
      IF MID$(passLine$, stripLen + 1, 1) = ":" THEN
        stripLen = stripLen + 1
      END IF
    END IF
  ELSE
    uFirst$ = UCASE$(firstChar$)
    IF (uFirst$ >= "A" AND uFirst$ <= "Z") THEN
      tempStrip = 0
      tempLabel$ = ""
      FOR iCheck = 1 TO LEN(passLine$)
        chCheck$ = UCASE$(MID$(passLine$, iCheck, 1))
        IF (chCheck$ >= "A" AND chCheck$ <= "Z") OR (chCheck$ >= "0" AND chCheck$ <= "9") OR chCheck$ = "_" THEN
          tempLabel$ = tempLabel$ + chCheck$
          tempStrip = tempStrip + 1
        ELSE
          EXIT FOR
        END IF
      NEXT
      IF tempStrip < LEN(passLine$) THEN
        IF MID$(passLine$, tempStrip + 1, 1) = ":" THEN
          isLabel = 1
          FOR iVoc = 512 TO 1023
            IF voc(iVoc).text <> "" THEN
              IF tempLabel$ = voc(iVoc).text THEN
                isLabel = 0
                EXIT FOR
              END IF
            END IF
          NEXT
          IF isLabel = 1 THEN
            tempLabelStr$ = tempLabel$
            stripLen = tempStrip + 1
          END IF
        END IF
      END IF
    END IF
  END IF

  IF isLabel = 0 THEN
    retLabelStripLength$ = ""
  ELSE
    return2 stripLen
    retLabelStripLength$ = tempLabelStr$
  END IF

END FUNCTION ' retLabelStripLength$

''''''''''''''''''''''''
FUNCTION retLineNumberStr$

  ' Returns the current line number as a formatted string
  retLineNumberStr$ = LTRIM$(RTRIM$(STR$(currentLineNumber)))

END FUNCTION ' retLineNumberStr$

''''''''''''''''''''''''
FUNCTION retRtOffsetByName (wName$)

  tempRet = RT_INVALID

  SELECT CASE wName$

    CASE "RT_KEYDOWN": tempRet = RT_KEYDOWN
    CASE "RT_LINE": tempRet = RT_LINE
    CASE "RT_PLOT_PIXEL": tempRet = RT_PLOT_PIXEL
    CASE "RT_STR_ASSIGN": tempRet = RT_STR_ASSIGN
    CASE "RT_VEH_HANDLER": tempRet = RT_VEH_HANDLER
    CASE "RT_PRINT_INT": tempRet = RT_PRINT_INT
    CASE "RT_PRINT_FLOAT": tempRet = RT_PRINT_FLOAT
    CASE "RT_PRINT_STR": tempRet = RT_PRINT_STR
    CASE "RT_CRLF": tempRet = RT_CRLF
    CASE "RT_INPUT": tempRet = RT_INPUT
    CASE "RT_GFX_APPEND": tempRet = RT_GFX_APPEND
    CASE "RT_STR_CMP": tempRet = RT_STR_CMP
    CASE "RT_GET": tempRet = RT_GET
    CASE "RT_PUT": tempRet = RT_PUT
    CASE "RT_SWAP_BUFFERS": tempRet = RT_SWAP_BUFFERS
    CASE "RT_FULLSCREEN": tempRet = RT_FULLSCREEN
    CASE "RT_AUTODISPLAY_CHECK": tempRet = RT_AUTODISPLAY_CHECK
    CASE "RT_CIRCLE": tempRet = RT_CIRCLE
    CASE "RT_READ": tempRet = RT_READ
    CASE "RT_MOUSEINPUT": tempRet = RT_MOUSEINPUT

  END SELECT ' wName$

  retRtOffsetByName = tempRet

END FUNCTION ' retRtOffsetByName

''''''''''''''''''''''''
FUNCTION retSymbolByteSize (vIdx)

  DIM paddedSize AS LONG
  DIM remainder AS LONG
  DIM dt AS LONG
  DIM fixedLen AS LONG

  dt = symbols(vIdx).DataType

  IF dt = TYPE_UNDEFINED THEN
    IF symbols(vIdx).SubIndex <> 0 THEN
      IF subs(symbols(vIdx).SubIndex).IsFunction = 0 THEN
        retSymbolByteSize = 0
        EXIT FUNCTION
      END IF
    END IF
    ESCAPETEXT2 "RSBS: FATAL IN retSymbolByteSize", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(vIdx).RecordName)
  END IF

  ' Dynamic array pointers are always exactly 8 bytes globally
  IF symbols(vIdx).IsArray = 2 THEN
    retSymbolByteSize = 8
    EXIT FUNCTION
  END IF

  paddedSize = 0

  SELECT CASE dt

    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE
      paddedSize = symbols(vIdx).Size * 8

    CASE TYPE_BYTE, TYPE_UBYTE, TYPE_INTEGER, TYPE_UINTEGER
      paddedSize = symbols(vIdx).Size
      IF dt = TYPE_INTEGER OR dt = TYPE_UINTEGER THEN paddedSize = paddedSize * 2
      remainder = paddedSize MOD 8
      IF remainder <> 0 THEN paddedSize = paddedSize + (8 - remainder)

    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE
      paddedSize = symbols(vIdx).Size * 4
      remainder = paddedSize MOD 8
      IF remainder <> 0 THEN paddedSize = paddedSize + (8 - remainder)

    CASE TYPE_STRING
      IF symbols(vIdx).IsArray = 1 THEN
        fixedLen = retFixedStringLength(vIdx)
        IF fixedLen > 0 THEN
          paddedSize = symbols(vIdx).Size * fixedLen
          remainder = paddedSize MOD 8
          IF remainder <> 0 THEN paddedSize = paddedSize + (8 - remainder)
        ELSE
          paddedSize = symbols(vIdx).Size * 8
        END IF
      ELSE
        ' Standalone Strings
        IF symbols(vIdx).IsLocal = 1 AND symbols(vIdx).IsShared = 0 AND LEFT$(symbols(vIdx).RecordName, 1) <> "~" THEN
          paddedSize = 24 ' Local strings put the 24-byte descriptor inline on the stack
        ELSE
          paddedSize = 8 ' Global strings and ephemeral TIRA pointers just put an 8-byte pointer
        END IF
      END IF

    CASE TYPE_UDT
      paddedSize = symbols(vIdx).Size * udts(symbols(vIdx).UDTIndex).TotalSize
      remainder = paddedSize MOD 8
      IF remainder <> 0 THEN paddedSize = paddedSize + (8 - remainder)

    CASE ELSE
      paddedSize = symbols(vIdx).Size * 8 ' Fallback safety

  END SELECT ' dt

  retSymbolByteSize = paddedSize

END FUNCTION ' retSymbolByteSize

''''''''''''''''''''''''
FUNCTION retTokenVal (wTok$)

  tRet = 0
  IF LEN(wTok$) = 2 THEN
    firstAsc = ASC(LEFT$(wTok$, 1))
    IF firstAsc < 32 THEN
      tRet = (firstAsc * 256) + ASC(MID$(wTok$, 2, 1))
    END IF
  END IF

  retTokenVal = tRet

END FUNCTION ' retTokenVal

''''''''''''''''''''''''
FUNCTION retTokenText$ (wTok$)

  ' For if I want parts of the code to be blind to token values
  ' Safely reconstructs strings for identifiers (0), ASCII symbols (256-511), and keywords (512-1023)

  tempRet$ = wTok$
  tVal = retTokenVal(wTok$)

  IF tVal <> 0 THEN
    IF tVal >= 256 AND tVal <= 511 THEN
      tempRet$ = CHR$(tVal - 256)
    ELSE
      IF tVal >= 512 AND tVal <= 1023 THEN
        IF voc(tVal).text <> "" THEN
          tempRet$ = voc(tVal).text
        END IF
      END IF
    END IF
  END IF

  retTokenText$ = tempRet$

END FUNCTION ' retTokenText$

''''''''''''''''''''''''
FUNCTION retTypeFromToken (tType AS LONG, isUnsigned AS LONG)

  DIM tempType AS LONG
  tempType = TYPE_UNDEFINED

  IF isUnsigned = 1 THEN

    SELECT CASE tType

      CASE TOK_BYTE
        tempType = TYPE_UBYTE
      CASE TOK_INTEGER
        tempType = TYPE_UINTEGER
      CASE TOK_LONG
        tempType = TYPE_ULONG
      CASE TOK_INTEGER64
        tempType = TYPE_UINT64

    END SELECT ' tType

  ELSE

    SELECT CASE tType

      CASE TOK_BYTE
        tempType = TYPE_BYTE
      CASE TOK_INTEGER
        tempType = TYPE_INTEGER
      CASE TOK_LONG
        tempType = TYPE_LONG
      CASE TOK_INTEGER64
        tempType = TYPE_INTEGER64
      CASE TOK_SINGLE
        tempType = TYPE_SINGLE
      CASE TOK_DOUBLE
        tempType = TYPE_DOUBLE
      CASE TOK_DSTRING
        tempType = TYPE_STRING
      CASE TOK_STRING
        tempType = TYPE_STRING
      CASE TOK_ANY
        tempType = TYPE_ANY

    END SELECT ' tType
  END IF

  retTypeFromToken = tempType

END FUNCTION ' retTypeFromToken

''''''''''''''''''''''''
SUB searchModal

  ' Give the modal a clean slate to prevent double-triggering inputs
  _KEYCLEAR

  DO
    limitSpeed
    mouseReadInput

    redrawAll

    boxW = 320
    boxH = 64
    boxX = (SCREENSIZEX - boxW) \ 2
    boxY = (SCREENSIZEY - boxH) \ 2

    drawBorderBox boxX, boxY, boxW, boxH, 15, editor.windowBarClr
    PrintStr boxX + (boxW \ 2) - 44, boxY + 3, "SEARCH FIND", 14, 0, 1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    closeBtnW = 15
    closeBtnH = 13
    closeBtnX = boxX + boxW - closeBtnW
    closeBtnY = boxY
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, 0, 1

    IF mouseClickedInBox(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
      EXIT DO
    END IF

    ' Input box
    inputBoxX = boxX + 16
    inputBoxY = boxY + 24
    inputBoxW = boxW - 32
    inputBoxH = 16
    drawBorderBox inputBoxX, inputBoxY, inputBoxW, inputBoxH, 15, 0

    ' Draw text
    PrintStr inputBoxX + 4, inputBoxY + 4, editorSearchQuery$ + "_", 15, 0, 1

    _DISPLAY

    kVal = _KEYHIT
    IF kVal <> 0 THEN
      IF kVal = 27 THEN ' ESC
        waitKeyRelease "ESC"
        EXIT DO
      END IF

      IF kVal = 13 THEN ' ENTER
        IF editorSearchQuery$ <> "" THEN
          findEditorNext
        END IF
        EXIT DO
      END IF

      IF kVal = 8 THEN ' Backspace
        qLen = LEN(editorSearchQuery$)
        IF qLen > 0 THEN
          editorSearchQuery$ = LEFT$(editorSearchQuery$, qLen - 1)
        END IF
      ELSE
        IF kVal >= 32 AND kVal <= 126 THEN
          IF LEN(editorSearchQuery$) < 34 THEN
            editorSearchQuery$ = editorSearchQuery$ + CHR$(kVal)
          END IF
        END IF
      END IF
    END IF

  LOOP

END SUB ' searchModal

''''''''''''''''''''''''
SUB setFlashText (wStr$, wTime)

  flashTextTimer = wTime
  flashText$ = wStr$

END SUB ' setFlashText

''''''''''''''''''''''''
SUB setPalettes256

  DIM rOrig AS _UNSIGNED LONG, gOrig AS _UNSIGNED LONG, bOrig AS _UNSIGNED LONG
  DIM rFinal AS _UNSIGNED LONG, gFinal AS _UNSIGNED LONG, bFinal AS _UNSIGNED LONG

  FOR ii = 1 TO 255
    rOrig = bmpPal256(ii, palRED)
    gOrig = bmpPal256(ii, palGREEN)
    bOrig = bmpPal256(ii, palBLUE)

    rFinal = rOrig AND 252
    gFinal = gOrig AND 252
    bFinal = bOrig AND 252

    _PALETTECOLOR ii, _RGB32(rFinal, gFinal, bFinal)
  NEXT

END SUB ' setPalettes256

''''''''''''''''''''''''
FUNCTION textFileRVA (wFileOffset)

  tempRet = PE_TEXT_VA + (wFileOffset - PE_FILE_HEADER_OFFSET)
  textFileRVA = tempRet

END FUNCTION ' textFileRVA

''''''''''''''''''''''''
SUB throwCompilerError (errMsg$, wType, wData)

  ' wData is a placeholder

  IF wType = ASIS THEN
    ' Centralized error helper to reduce boilerplate formatting as the compiler grows
    addStatusMsg "ERROR line " + retLineNumberStr$ + ": " + errMsg$
  ELSE ' WITHFAILED:
    addStatusMsg "ERROR line " + retLineNumberStr$ + ": " + errMsg$ + " FAILED"
  END IF

END SUB ' throwCompilerError

'''''''''''''''''''''''
SUB throwCompilerErrorAndCancelTira (errMsg$, wType, wData)

  ' Combines two frequently used calls into one

  tira_Cancel

  ' wData is a placeholder

  IF wType = ASIS THEN
    ' Centralized error helper to reduce boilerplate formatting as the compiler grows
    addStatusMsg "ERROR line " + retLineNumberStr$ + ": " + errMsg$
  ELSE ' WITHFAILED:
    addStatusMsg "ERROR line " + retLineNumberStr$ + ": " + errMsg$ + " FAILED"
  END IF

END SUB ' throwCompilerError

'''''''''''''''''''''''
FUNCTION tasmEndHelper_JMP_COND (condCodeStr$, src1Str$, src2Str$, targetLabel$)

  IF t.IsActive <> 2 THEN
    throwCompilerError "tasmEndHelper_JMP_COND: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    tasmEndHelper_JMP_COND = 0
    EXIT FUNCTION
  END IF

  DIM dt1 AS LONG
  DIM dt2 AS LONG
  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM targetMode AS LONG
  DIM opModeFloat AS LONG
  DIM pushedDummy AS LONG
  DIM jmpType AS LONG
  DIM vIdx AS LONG

  firstChar$ = LEFT$(targetLabel$, 1)
  IF firstChar$ <> "@" THEN
    throwCompilerError "Internal jump targets must use @ prefix", ASIS, 0
    tasmEndHelper_JMP_COND = 0
    EXIT FUNCTION
  END IF

  ' Determine DataType of src1
  dt1 = TYPE_LONG
  firstChar$ = LEFT$(src1Str$, 1)
  IF firstChar$ = CHR$(34) THEN
    dt1 = TYPE_STRING
  ELSE
    IF (firstChar$ >= "0" AND firstChar$ <= "9") OR firstChar$ = "-" OR firstChar$ = "." OR (firstChar$ = "&" AND (UCASE$(MID$(src1Str$, 2, 1)) = "H" OR UCASE$(MID$(src1Str$, 2, 1)) = "O")) THEN
      IF INSTR(src1Str$, ".") > 0 THEN dt1 = TYPE_DOUBLE ELSE dt1 = TYPE_LONG
    ELSE
      ff = resolveSymbol(src1Str$)
      IF ff = 1 THEN
        dt1 = returnedData3
      END IF
    END IF
  END IF

  ' Determine DataType of src2
  dt2 = TYPE_LONG
  firstChar$ = LEFT$(src2Str$, 1)
  IF firstChar$ = CHR$(34) THEN
    dt2 = TYPE_STRING
  ELSE
    IF (firstChar$ >= "0" AND firstChar$ <= "9") OR firstChar$ = "-" OR firstChar$ = "." OR (firstChar$ = "&" AND (UCASE$(MID$(src2Str$, 2, 1)) = "H" OR UCASE$(MID$(src2Str$, 2, 1)) = "O")) THEN
      IF INSTR(src2Str$, ".") > 0 THEN dt2 = TYPE_DOUBLE ELSE dt2 = TYPE_LONG
    ELSE
      ff = resolveSymbol(src2Str$)
      IF ff = 1 THEN
        dt2 = returnedData3
      END IF
    END IF
  END IF

  tasm_LoadOperand src1Str$, 0
  isFloat1 = returnedData2
  tasm_LoadOperand src2Str$, 3
  isFloat2 = returnedData2

  IF dt1 = TYPE_STRING AND dt2 = TYPE_STRING THEN
    opPushReg 1
    opPushReg 2

    ' String Compare Block
    ' Move descriptors from RAX(0) and RBX(3) into RCX(1) and RDX(2) for ABI
    ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
    ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 3, 64)

    pushedDummy = 0
    IF updateStackAlignment = 0 THEN
      opPushReg 13
      pushedDummy = 1
    END IF

    ' Allocate 32 bytes shadow space to prevent prologue stack corruption
    ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
    stack.currentStackOffset = stack.currentStackOffset + 32
    ff = updateStackAlignment

    rtIsUsed(RT_STR_CMP) = 1
    addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_CMP
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      tasmEndHelper_JMP_COND = 0
      EXIT FUNCTION
    END IF

    ' Restore shadow space
    ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
    stack.currentStackOffset = stack.currentStackOffset - 32
    ff = updateStackAlignment

    IF pushedDummy = 1 THEN
      opPopReg 13
    END IF

    opPopReg 2
    opPopReg 1

    ' Result is in RAX (0). Compare with 0.
    ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, 0, 64)

    jmpType = JCC_JE

    SELECT CASE condCodeStr$

      CASE "JE", "EQ": jmpType = JCC_JE
      CASE "JNE", "NE": jmpType = JCC_JNE
      CASE "JL", "LT": jmpType = JCC_JL
      CASE "JLE", "LE": jmpType = JCC_JLE
      CASE "JG", "GT": jmpType = JCC_JG
      CASE "JGE", "GE": jmpType = JCC_JGE

    END SELECT ' condCodeStr$

  ELSE
    IF isFloat1 > 0 OR isFloat2 > 0 THEN
      targetMode = MODE_SSE_DOUBLE
      IF isFloat1 = 1 AND isFloat2 = 1 THEN targetMode = MODE_SSE_SINGLE

      IF isFloat1 = 0 THEN
        ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, targetMode)
      ELSE
        IF isFloat1 = 1 AND targetMode = MODE_SSE_DOUBLE THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
        END IF
      END IF

      IF isFloat2 = 0 THEN
        ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 3, targetMode)
      ELSE
        opModeFloat = MODE_SSE_DOUBLE
        IF isFloat2 = 1 THEN opModeFloat = MODE_SSE_SINGLE
        ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 3, opModeFloat)
        IF isFloat2 = 1 AND targetMode = MODE_SSE_DOUBLE THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 1, MODE_SSE_SINGLE)
        END IF
      END IF

      ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)

      jmpType = JCC_JE

      SELECT CASE condCodeStr$

        CASE "JE", "EQ": jmpType = JCC_JE
        CASE "JNE", "NE": jmpType = JCC_JNE
        CASE "JL", "LT": jmpType = JCC_JB
        CASE "JLE", "LE": jmpType = JCC_JBE
        CASE "JG", "GT": jmpType = JCC_JA
        CASE "JGE", "GE": jmpType = JCC_JAE

      END SELECT ' condCodeStr$

    ELSE
      ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)

      jmpType = JCC_JE

      SELECT CASE condCodeStr$

        CASE "JE", "EQ": jmpType = JCC_JE
        CASE "JNE", "NE": jmpType = JCC_JNE
        CASE "JL", "LT": jmpType = JCC_JL
        CASE "JLE", "LE": jmpType = JCC_JLE
        CASE "JG", "GT": jmpType = JCC_JG
        CASE "JGE", "GE": jmpType = JCC_JGE

      END SELECT ' condCodeStr$

    END IF
  END IF

  ff = resolveSymbol(targetLabel$)
  IF ff = 1 THEN
    vIdx = returnedData2
    addPatch PATCH_GOTO, opJcc(jmpType, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx
  END IF
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    tasmEndHelper_JMP_COND = 0
    EXIT FUNCTION
  END IF

  tasmEndHelper_JMP_COND = 1

END FUNCTION ' tasmEndHelper_JMP_COND

'''''''''''''''''''''''
SUB tasm_DoCast (dest$, src$, targetTypeStr$)

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_DoCast: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM dtDest AS LONG
  DIM dtSrc AS LONG
  DIM isFloat AS LONG

  dtDest = tasm_GetOperandType(dest$)
  dtSrc = tasm_GetOperandType(src$)

  IF dtDest = TYPE_STRING OR dtSrc = TYPE_STRING THEN
    throwCompilerError "CANNOT CAST STRINGS", ASIS, 0
    EXIT SUB
  END IF

  tasm_LoadOperand src$, 0
  isFloat = returnedData2

  tasm_StoreOperand dest$, 0, isFloat

END SUB ' tasm_DoCast

''''''''''''''''''''''''
SUB tasm_DoMath (opCmd AS LONG, dest$, src1$, src2$)

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_DoMath: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  ' tasm_ functions are back end functions designed to be called by tira_EndAndProcess, or another tasm_ function
  ' These functions do not sit between a tira_Start and a tira_EndAndProcess. They can output raw assembly

  DIM dtDest AS LONG
  DIM dt1 AS LONG
  DIM dt2 AS LONG
  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM targetMode AS LONG
  DIM resIsFloat AS LONG
  DIM opModeFloat AS LONG

  dtDest = tasm_GetOperandType(dest$)
  dt1 = tasm_GetOperandType(src1$)
  dt2 = tasm_GetOperandType(src2$)

  IF opCmd = TC_CONCAT THEN
    IF dtDest <> TYPE_STRING OR dt1 <> TYPE_STRING OR dt2 <> TYPE_STRING THEN
      throwCompilerError "TC_CONCAT REQUIRES STRINGS", ASIS, 0
      EXIT SUB
    END IF

    opPushReg 12 ' Protect ABI non-volatile string descriptors
    opPushReg 13
    opPushReg 14

    tasm_LoadOperand src1$, 0
    isFloat1 = returnedData2
    tasm_LoadOperand src2$, 3
    isFloat2 = returnedData2

    ff = genLoadStringDesc(0, 12, 13)
    ff = genLoadStringDesc(3, 10, 11)

    ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, internalTempHeapSymbolIdx)

    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 13, 64)
    ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_REG, 11, 64)

    ' Corrected memory allocation logic to prevent the 24-byte descriptor from overwriting the string data
    ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_IMM, 24, 64)
    ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_REG, 8, 64)
    ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

    genBlockTransfer 12, 7, 13
    genBlockTransfer 10, 7, 11

    ' R7 natively points precisely to the correct 24-byte descriptor slot after genBlockTransfer completes
    ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 14, 64)
    ff = opMov(OP_TYPE_MEM_REG_DISP8, 7 + (8 * 256), OP_TYPE_REG, 8, 64)

    ' Explicitly clear the Flags value to 0 to prevent garbage data from triggering double-frees during Garbage Collection
    ff = opALU(ALU_XOR, OP_TYPE_REG, 9, OP_TYPE_REG, 9, 64)
    ff = opMov(OP_TYPE_MEM_REG_DISP8, 7 + (16 * 256), OP_TYPE_REG, 9, 64)

    ' Update !G_MEM_TEMP_HEAP_PTR to the lowest address (R14), not the descriptor address (R7)
    ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 14, 64, internalTempHeapSymbolIdx)

    ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 7, 64)
    tasm_StoreOperand dest$, 0, 0

    opPopReg 14 ' Restore ABI non-volatile string descriptors
    opPopReg 13
    opPopReg 12

    EXIT SUB
  END IF

  IF dtDest = TYPE_STRING OR dt1 = TYPE_STRING OR dt2 = TYPE_STRING THEN
    throwCompilerError "MATH OP WITH STRING", ASIS, 0
    EXIT SUB
  END IF

  tasm_LoadOperand src1$, 0
  isFloat1 = returnedData2
  tasm_LoadOperand src2$, 3
  isFloat2 = returnedData2

  ' Force float-to-integer conversion for strict integer instructions before they hit the math flow
  IF opCmd = TC_IDIV OR opCmd = TC_MOD OR opCmd = TC_AND OR opCmd = TC_OR THEN
    IF isFloat1 > 0 THEN
      opModeFloat = MODE_SSE_DOUBLE
      IF isFloat1 = 1 THEN opModeFloat = MODE_SSE_SINGLE
      ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opModeFloat)
      isFloat1 = 0
    END IF
    IF isFloat2 > 0 THEN
      opModeFloat = MODE_SSE_DOUBLE
      IF isFloat2 = 1 THEN opModeFloat = MODE_SSE_SINGLE
      ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 3, OP_TYPE_REG, 3, opModeFloat)
      isFloat2 = 0
    END IF
  END IF

  IF isFloat1 > 0 OR isFloat2 > 0 OR opCmd = TC_POW OR opCmd = TC_DIV THEN
    targetMode = MODE_SSE_DOUBLE
    IF opCmd <> TC_POW THEN
      IF isFloat1 = 1 AND isFloat2 = 1 THEN targetMode = MODE_SSE_SINGLE
      IF isFloat1 = 0 AND isFloat2 = 0 AND opCmd = TC_DIV THEN targetMode = MODE_SSE_SINGLE
    END IF

    IF isFloat1 = 0 THEN
      ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, targetMode)
    ELSE
      IF isFloat1 = 1 AND targetMode = MODE_SSE_DOUBLE THEN
        ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
      END IF
    END IF

    IF isFloat2 = 0 THEN
      ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 3, targetMode)
    ELSE
      opModeFloat = MODE_SSE_DOUBLE
      IF isFloat2 = 1 THEN opModeFloat = MODE_SSE_SINGLE
      ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 3, opModeFloat)
      IF isFloat2 = 1 AND targetMode = MODE_SSE_DOUBLE THEN
        ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 1, MODE_SSE_SINGLE)
      END IF
    END IF

    IF opCmd = TC_POW THEN
      ff = genAlignedCall(IAT_POW, 13, DEFAULT)
    ELSE

      SELECT CASE opCmd

        CASE TC_ADD: ff = opSSE(SSE_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
        CASE TC_SUB: ff = opSSE(SSE_SUB, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
        CASE TC_MUL: ff = opSSE(SSE_MUL, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
        CASE TC_DIV: ff = opSSE(SSE_DIV, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)

      END SELECT ' opCmd

    END IF

    resIsFloat = 2
    IF targetMode = MODE_SSE_SINGLE THEN resIsFloat = 1
    tasm_StoreOperand dest$, 0, resIsFloat
  ELSE

    SELECT CASE opCmd

      CASE TC_ADD: ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
      CASE TC_SUB: ff = opALU(ALU_SUB, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
      CASE TC_MUL: ff = opImul(0, OP_TYPE_REG, 3, 0, MODE_IMUL64_REG)
      CASE TC_IDIV
        opPushReg 2
        opExtend EXTEND_CQO
        ff = opUnary(UNARY_IDIV, OP_TYPE_REG, 3, 64)
        opPopReg 2
      CASE TC_MOD
        opPushReg 2
        opExtend EXTEND_CQO
        ff = opUnary(UNARY_IDIV, OP_TYPE_REG, 3, 64)
        ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 2, 64)
        opPopReg 2
      CASE TC_AND: ff = opALU(ALU_AND, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
      CASE TC_OR: ff = opALU(ALU_OR, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
      CASE TC_COMPARE
        src1Str$ = dest$
        src2Str$ = src1$

        ' Determine DataType of src1
        dt1 = TYPE_LONG
        firstCh$ = LEFT$(src1Str$, 1)
        IF firstCh$ = CHR$(34) THEN
          dt1 = TYPE_STRING
        ELSE
          IF (firstCh$ >= "0" AND firstCh$ <= "9") OR firstCh$ = "-" OR firstCh$ = "." OR (firstCh$ = "&" AND (UCASE$(MID$(src1Str$, 2, 1)) = "H" OR UCASE$(MID$(src1Str$, 2, 1)) = "O")) THEN
            IF INSTR(src1Str$, ".") > 0 THEN dt1 = TYPE_DOUBLE ELSE dt1 = TYPE_LONG
          ELSE
            ff = resolveSymbol(src1Str$)
            IF ff = 1 THEN
              vIdx1 = returnedData2
              dt1 = returnedData3
            END IF
          END IF
        END IF

        ' Determine DataType of src2
        dt2 = TYPE_LONG
        firstCh$ = LEFT$(src2Str$, 1)
        IF firstCh$ = CHR$(34) THEN
          dt2 = TYPE_STRING
        ELSE
          IF (firstCh$ >= "0" AND firstCh$ <= "9") OR firstCh$ = "-" OR firstCh$ = "." OR (firstCh$ = "&" AND (UCASE$(MID$(src2Str$, 2, 1)) = "H" OR UCASE$(MID$(src2Str$, 2, 1)) = "O")) THEN
            IF INSTR(src2Str$, ".") > 0 THEN dt2 = TYPE_DOUBLE ELSE dt2 = TYPE_LONG
          ELSE
            ff = resolveSymbol(src2Str$)
            IF ff = 1 THEN
              vIdx2 = returnedData2
              dt2 = returnedData3
            END IF
          END IF
        END IF

        tasm_LoadOperand src1Str$, 0
        isFloat1 = returnedData2
        tasm_LoadOperand src2Str$, 3
        isFloat2 = returnedData2

        IF dt1 = TYPE_STRING AND dt2 = TYPE_STRING THEN
          opPushReg 1
          opPushReg 2

          ' String Compare Block
          ' Move descriptors from RAX(0) and RBX(3) into RCX(1) and RDX(2) for ABI
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 3, 64)

          pushedDummy = 0
          IF updateStackAlignment = 0 THEN
            opPushReg 13
            pushedDummy = 1
          END IF

          ' Allocate 32 bytes shadow space to prevent prologue stack corruption
          ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
          stack.currentStackOffset = stack.currentStackOffset + 32
          ff = updateStackAlignment

          rtIsUsed(RT_STR_CMP) = 1
          addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_CMP
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            tira_Cancel
            EXIT SUB
          END IF

          ' Restore shadow space
          ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
          stack.currentStackOffset = stack.currentStackOffset - 32
          ff = updateStackAlignment

          IF pushedDummy = 1 THEN
            opPopReg 13
          END IF

          opPopReg 2
          opPopReg 1

          ' Result is in RAX (0). Compare with 0.
          ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, 0, 64)
        ELSE
          IF isFloat1 > 0 OR isFloat2 > 0 THEN
            targetMode = MODE_SSE_DOUBLE
            IF isFloat1 = 1 AND isFloat2 = 1 THEN targetMode = MODE_SSE_SINGLE

            IF isFloat1 = 0 THEN
              ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, targetMode)
            ELSE
              IF isFloat1 = 1 AND targetMode = MODE_SSE_DOUBLE THEN
                ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
              END IF
            END IF

            IF isFloat2 = 0 THEN
              ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 3, targetMode)
            ELSE
              opModeFloat = MODE_SSE_DOUBLE:
              IF isFloat2 = 1 THEN opModeFloat = MODE_SSE_SINGLE
              ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 3, opModeFloat)
              IF isFloat2 = 1 AND targetMode = MODE_SSE_DOUBLE THEN
                ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 1, MODE_SSE_SINGLE)
              END IF
            END IF

            ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
          ELSE
            ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
          END IF
        END IF
        EXIT SUB

    END SELECT ' opCmd

    tasm_StoreOperand dest$, 0, 0
  END IF

END SUB ' tasm_DoMath

''''''''''''''''''''''''
SUB tasm_DoShift (opCmd AS LONG, dest$, src1$, src2$)

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_DoShift: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM dtDest AS LONG
  DIM dt1 AS LONG
  DIM dt2 AS LONG
  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM opMode AS LONG

  dtDest = tasm_GetOperandType(dest$)
  dt1 = tasm_GetOperandType(src1$)
  dt2 = tasm_GetOperandType(src2$)

  IF dtDest = TYPE_STRING OR dt1 = TYPE_STRING OR dt2 = TYPE_STRING THEN
    throwCompilerError "SHIFT OP WITH STRING", ASIS, 0
    EXIT SUB
  END IF

  opPushReg 1

  tasm_LoadOperand src1$, 0
  isFloat1 = returnedData2
  tasm_LoadOperand src2$, 1
  isFloat2 = returnedData2

  IF isFloat1 > 0 THEN
    opMode = MODE_SSE_DOUBLE
    IF isFloat1 = 1 THEN opMode = MODE_SSE_SINGLE
    ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
  END IF

  IF isFloat2 > 0 THEN
    opMode = MODE_SSE_DOUBLE
    IF isFloat2 = 1 THEN opMode = MODE_SSE_SINGLE
    ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 1, OP_TYPE_REG, 1, opMode)
  END IF

  ' REX.W (64-bit operation)
  emitByteCode &H48

  ' D3 = SHL/SHR r/m64, CL
  emitByteCode &HD3

  IF opCmd = TC_SHL THEN
    emitByteCode &HE0 ' 11 100 000 (mod=3, reg=4 for SHL, rm=0 for RAX)
  ELSE
    emitByteCode &HE8 ' 11 101 000 (mod=3, reg=5 for SHR, rm=0 for RAX)
  END IF

  opPopReg 1

  tasm_StoreOperand dest$, 0, 0

END SUB ' tasm_DoShift

''''''''''''''''''''''''
SUB tasm_DoSwap (addr1$, addr2$, sizeMode$)

  IF t.IsActive <> 2 THEN
    throwCompilerError "tasm_DoSwap: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM opSize AS LONG

  tasm_LoadOperand addr1$, 10
  tasm_LoadOperand addr2$, 11

  opSize = 64
  SELECT CASE sizeMode$

    CASE "1": opSize = 8
    CASE "2": opSize = 16
    CASE "4": opSize = 32
    CASE "8": opSize = 64
    CASE "SINGLE": opSize = 32
    CASE "DOUBLE": opSize = 64

  END SELECT ' sizeMode$

  ' Read the memory values into our primary compute registers
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, opSize)
  ff = opMov(OP_TYPE_REG, 3, OP_TYPE_MEM_REG, 11, opSize)

  ' Write the values back to the swapped addresses
  ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 3, opSize)
  ff = opMov(OP_TYPE_MEM_REG, 11, OP_TYPE_REG, 0, opSize)

END SUB ' tasm_DoSwap

''''''''''''''''''''''''
SUB tasm_DoUnary (opCmd AS LONG, dest$, src$)

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_DoUnary: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM dtDest AS LONG
  DIM dtSrc AS LONG
  DIM isFloat AS LONG
  DIM opMode AS LONG

  dtDest = tasm_GetOperandType(dest$)
  dtSrc = tasm_GetOperandType(src$)

  IF dtDest = TYPE_STRING OR dtSrc = TYPE_STRING THEN
    throwCompilerError "UNARY OP WITH STRING", ASIS, 0
    EXIT SUB
  END IF

  tasm_LoadOperand src$, 0
  isFloat = returnedData2

  IF isFloat > 0 THEN
    opMode = MODE_SSE_DOUBLE
    IF isFloat = 1 THEN opMode = MODE_SSE_SINGLE
    ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
    isFloat = 0
  END IF

  IF opCmd = TC_NEG THEN
    ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)
  ELSE
    ff = opUnary(UNARY_NOT, OP_TYPE_REG, 0, 64)
  END IF

  tasm_StoreOperand dest$, 0, isFloat

END SUB ' tasm_DoUnary

''''''''''''''''''''''''
FUNCTION tasm_GetOperandType (opStr$)

  DIM dt AS LONG
  DIM firstCh AS STRING * 1

  dt = TYPE_LONG
  firstCh = LEFT$(opStr$, 1)

  IF firstCh = CHR$(34) THEN
    dt = TYPE_STRING
  ELSE
    IF (firstCh >= "0" AND firstCh <= "9") OR firstCh = "-" OR firstCh = "." OR (firstCh = "&" AND (UCASE$(MID$(opStr$, 2, 1)) = "H" OR UCASE$(MID$(opStr$, 2, 1)) = "O")) THEN
      IF INSTR(opStr$, ".") > 0 THEN dt = TYPE_DOUBLE ELSE dt = TYPE_LONG
    ELSE
      ff = resolveSymbol(opStr$)
      IF ff = 1 THEN
        dt = returnedData3
      END IF
    END IF
  END IF

  tasm_GetOperandType = dt

END FUNCTION ' tasm_GetOperandType

''''''''''''''''''''''''
SUB tasm_LoadOperand (opStr$, destReg AS LONG)

  ' Parses an operand string, resolves its scope, and generates the instructions to load its value into a
  ' destination register. It manages inline literals by dynamically registering them in the symbol table
  ' so they can be allocated in the data segment

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_LoadOperand: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM firstChar AS STRING * 1
  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM opMode AS LONG
  DIM isFloat AS LONG

  firstChar = LEFT$(opStr$, 1)

  IF firstChar = "@" THEN
    throwCompilerError "FATAL: @ prefix reserved for Jump Labels. Use TC_ADDRESS_OF", ASIS, 0
    return2 0
    EXIT SUB
  END IF

  IF (firstChar >= "0" AND firstChar <= "9") OR firstChar = "-" OR firstChar = "." OR firstChar = CHR$(34) OR (firstChar = "&" AND (UCASE$(MID$(opStr$, 2, 1)) = "H" OR UCASE$(MID$(opStr$, 2, 1)) = "O")) THEN
    IF firstChar = CHR$(34) THEN
      lit$ = extractQuotes$(opStr$)
      ff = resolveSymbol("!G_EVAL_LIT__" + cTrNum$(t.TiraVarCounter) + "_DESC$")
      t.TiraVarCounter = t.TiraVarCounter + 1
      IF ff = 1 THEN
        vIdx = returnedData2
        strVarData$(vIdx) = lit$
      ELSE
        throwCompilerError "LITERAL ALLOCATION FAILED IN BACKEND", ASIS, 0
        return2 0
        EXIT SUB
      END IF
      ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)
      isFloat = 0
    ELSE
      IF INSTR(opStr$, ".") > 0 THEN
        ff = resolveSymbol("!G_EVAL_FLT_" + cTrNum$(t.TiraVarCounter) + "_VAL")
        t.TiraVarCounter = t.TiraVarCounter + 1
        IF ff = 1 THEN
          vIdx = returnedData2
          symbols(vIdx).DataType = TYPE_DOUBLE
          floatVarData(vIdx) = VAL(opStr$)
          ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_SSE_DOUBLE, vIdx)
        ELSE
          throwCompilerError "FLOAT LITERAL ALLOCATION FAILED IN BACKEND", ASIS, 0
          return2 0
          EXIT SUB
        END IF
        isFloat = 2
      ELSE
        ff = opMov(OP_TYPE_REG, destReg, OP_TYPE_IMM, VAL(opStr$), MODE_IMM64)
        isFloat = 0
      END IF
    END IF
  ELSE
    IF firstChar = "#" THEN
      vIdx = VAL(MID$(opStr$, 2))
      dt = symbols(vIdx).DataType
    ELSE
      ff = resolveSymbol(opStr$)
      IF ff = 1 THEN
        vIdx = returnedData2
        dt = returnedData3
      ELSE
        throwCompilerError "SYMBOL NOT FOUND IN BACKEND: " + opStr$, ASIS, 0
        return2 0
        EXIT SUB
      END IF
    END IF

    IF dt = TYPE_SINGLE OR dt = TYPE_DOUBLE THEN
      opMode = MODE_SSE_DOUBLE
      IF dt = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
      ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, opMode, vIdx)
      IF dt = TYPE_SINGLE THEN isFloat = 1 ELSE isFloat = 2
    ELSE
      IF dt = TYPE_STRING THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)
      ELSE

        SELECT CASE dt

          CASE TYPE_BYTE: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_MOVSX64_8, vIdx)
          CASE TYPE_UBYTE: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_MOVZX64_8, vIdx)
          CASE TYPE_INTEGER: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_MOVSX64_16, vIdx)
          CASE TYPE_UINTEGER: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_MOVZX64_16, vIdx)
          CASE TYPE_LONG: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_MOVSXD, vIdx)
          CASE TYPE_ULONG, TYPE_SINGLE: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 32, vIdx)
          CASE TYPE_INTEGER64, TYPE_UINT64: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)
          CASE ELSE: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)

        END SELECT ' dt

      END IF
      isFloat = 0
    END IF
  END IF

  return2 isFloat

END SUB ' tasm_LoadOperand

''''''''''''''''''''''''
SUB tasm_ProbeStack (allocSize AS LONG)

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_ProbeStack: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM probeLoop AS LONG
  DIM jmpDone AS LONG

  IF allocSize < 4096 THEN
    IF allocSize > 0 THEN
      opSubRsp32 allocSize
    END IF
    EXIT SUB
  END IF

  ' Move total allocation size into R11
  ff = opMov(OP_TYPE_REG, 11, OP_TYPE_IMM, allocSize, 64)

  probeLoop = stream.emitPos

  ' sub rsp, 4096
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 4096, 64)

  ' or byte ptr [rsp], 0 (Touch the guard page to commit the memory)
  ff = opALU(ALU_OR, OP_TYPE_MEM_RSP, 0, OP_TYPE_IMM, 0, 8)

  ' sub r11, 4096
  ff = opALU(ALU_SUB, OP_TYPE_REG, 11, OP_TYPE_IMM, 4096, 64)

  ' cmp r11, 4096
  ff = opALU(ALU_CMP, OP_TYPE_REG, 11, OP_TYPE_IMM, 4096, 64)

  ' jge probeLoop
  ff = opJcc(JCC_JGE, JCC_MODE_BACKWARD, probeLoop, JCC_TYPE_SHORT)

  ' test r11, r11
  ff = opTest(OP_TYPE_REG, 11, OP_TYPE_REG, 11, 64)
  jmpDone = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' sub rsp, r11
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_REG, 11, 64)

  stack.currentStackOffset = stack.currentStackOffset + allocSize
  ff = updateStackAlignment

  patch8 jmpDone

END SUB ' tasm_ProbeStack

''''''''''''''''''''''''
SUB tasm_RestoreVolatiles

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_RestoreVolatiles: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  opPopReg 11
  opPopReg 10
  opPopReg 9
  opPopReg 8
  opPopReg 2
  opPopReg 1

END SUB ' tasm_RestoreVolatiles

''''''''''''''''''''''''
SUB tasm_SaveVolatiles

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_SaveVolatiles: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  opPushReg 1
  opPushReg 2
  opPushReg 8
  opPushReg 9
  opPushReg 10
  opPushReg 11

END SUB ' tasm_SaveVolatiles

''''''''''''''''''''''''
SUB tasm_StoreOperand (opStr$, srcReg AS LONG, isFloat AS LONG)

  ' Generates the instructions to write a value from a source register into a target operand variable.
  ' It handles data type conversions, floating-point coercions, and string assignments based on the
  ' destination type

  IF t.IsActive <> 2 THEN ' Make sure this function was called in a TIRA block
    throwCompilerError "tasm_StoreOperand: TIRA NOT IN SETTING 2, NO tira_EndAndProcess CALL", ASIS, 0
    EXIT SUB
  END IF

  DIM vIdx AS LONG
  DIM targetType AS LONG
  DIM opMode AS LONG
  DIM pushedDummy AS LONG

  IF LEFT$(opStr$, 1) = "#" THEN
    vIdx = VAL(MID$(opStr$, 2))
    targetType = symbols(vIdx).DataType
  ELSE
    ff = resolveSymbol(opStr$)
    IF ff = 1 THEN
      vIdx = returnedData2
      targetType = returnedData3
    ELSE
      throwCompilerError "SYMBOL NOT FOUND IN BACKEND: " + opStr$, ASIS, 0
      EXIT SUB
    END IF
  END IF

  IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
    IF isFloat = 0 THEN
      ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, srcReg, OP_TYPE_REG, srcReg, MODE_SSE_DOUBLE)
      isFloat = 2
    END IF

    IF isFloat = 2 AND targetType = TYPE_SINGLE THEN
      ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, srcReg, OP_TYPE_REG, srcReg, MODE_SSE_DOUBLE)
      isFloat = 1
    END IF
    IF isFloat = 1 AND targetType = TYPE_DOUBLE THEN
      ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, srcReg, OP_TYPE_REG, srcReg, MODE_SSE_SINGLE)
      isFloat = 2
    END IF

    opMode = MODE_SSE_DOUBLE
    IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
    ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, opMode, vIdx)
  ELSE
    IF isFloat > 0 THEN
      opMode = MODE_SSE_DOUBLE
      IF isFloat = 1 THEN opMode = MODE_SSE_SINGLE
      ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, srcReg, OP_TYPE_REG, srcReg, opMode)
    END IF

    SELECT CASE targetType

      CASE TYPE_BYTE, TYPE_UBYTE
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 8, vIdx)
      CASE TYPE_INTEGER, TYPE_UINTEGER
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 16, vIdx)
      CASE TYPE_LONG, TYPE_ULONG
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 32, vIdx)
      CASE TYPE_INTEGER64, TYPE_UINT64
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 64, vIdx)
      CASE TYPE_STRING
        IF LEFT$(symbols(vIdx).RecordName, 1) = "~" THEN
          ' Safe pointer routing for temporary TIRA variables
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 64, vIdx)
        ELSE
          ' Full safety for true string assignment
          opPushReg 1
          opPushReg 2

          IF srcReg <> 2 THEN ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, srcReg, 64)
          ff = genSymbolRouteLea(1, vIdx)

          opPushReg 8
          opPushReg 9
          opPushReg 10
          opPushReg 11

          pushedDummy = 0
          IF updateStackAlignment = 0 THEN
            opPushReg 13
            pushedDummy = 1
          END IF

          ' Allocate 32 bytes shadow space to prevent prologue stack corruption
          ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
          stack.currentStackOffset = stack.currentStackOffset + 32
          ff = updateStackAlignment

          rtIsUsed(RT_STR_ASSIGN) = 1
          addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

          ' Restore shadow space
          ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
          stack.currentStackOffset = stack.currentStackOffset - 32
          ff = updateStackAlignment

          IF pushedDummy = 1 THEN
            opPopReg 13
          END IF

          opPopReg 11
          opPopReg 10
          opPopReg 9
          opPopReg 8

          opPopReg 2
          opPopReg 1
        END IF
      CASE ELSE
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 64, vIdx)

    END SELECT ' targetType

  END IF

END SUB ' tasm_StoreOperand

''''''''''''''''''''''''
SUB tira_Cancel

  t.IsActive = 0

END SUB 'tira_Cancel

''''''''''''''''''''''''
SUB tira_EndAndProcess

  t.IsActive = 2

  '''' Tira register allocation and ABI protection rules
  ' The TIRA backend operates as a memory-to-memory intermediate representation.
  ' To prevent internal calculations from silently corrupting the Windows x64 ABI
  ' volatile parameter registers (RCX, RDX, R8, R9) during execution, the tasm_
  ' suite enforces a strict register partitioning protocol:
  '
  ' RAX (0) and RBX (3): These act as TIRA's primary computational targets.
  ' Mathematical operations and general scalar evaluations natively resolve here.
  '
  ' R10 (10) and R11 (11): These serve as TIRA's exclusive safe scratchpads.
  ' They handle pointer indirection, array scaling (LEA_SIB), memory extraction,
  ' and data shuffling without risking ABI collisions.
  '
  ' RCX (1) and RDX (2): These are heavily restricted volatile ABI registers.
  ' The x64 processor hardware physically mandates their use for certain
  ' operations, such as CL for variable bit-shifting (SHL/SHR), RDX for division
  ' and modulo (IDIV), and RCX for block memory transfers (REP MOVSB/STOSB).
  ' Whenever TIRA executes these specific instructions, the registers are
  ' structurally shielded via opPushReg and opPopReg to preserve the ABI state.
  '
  ' R8 (8) and R9 (9): Volatile ABI registers left entirely untouched by internal
  ' TIRA math, reserved strictly for tiraCall parameter routing.
  '
  ' RSP (4) and RBP (5): Protected hardware stack and frame pointers. These are
  ' completely locked out of general scratchpad usage to prevent stack desyncs.
  '
  ' RDI (7) and RSI (6): Dedicated indexing registers used for block memory ops
  ' (TC_MEMCPY and TC_MEMSET). They are globally protected by the subroutine
  ' frame builder (TC_ENTER_FRAME) to comply with x64 non-volatile rules.

  DIM args$(32)
  DIM aCount AS LONG
  DIM vIdx AS LONG
  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM opMode AS LONG
  DIM pushedDummy AS LONG
  DIM allocSize AS LONG
  DIM cmdNum AS LONG

  DIM jmpType AS LONG
  DIM firstChar AS STRING * 1
  DIM dispVal AS LONG

  DIM argIdx AS LONG
  DIM srcVIdx AS LONG
  DIM stackOffset AS LONG

  DIM memOpTypeR AS LONG
  DIM memOpTypeW AS LONG

  DIM inQuotes AS LONG
  DIM aLen AS LONG
  DIM currArg$

  FOR ii = 0 TO t.LineCount - 1
    cmdNum = tiraCmd(ii)

    IF cmdNum = TC_INVALID THEN
      throwCompilerError "INVALID TIRA COMMAND (0)", ASIS, 0
      t.IsActive = 0
      EXIT SUB
    END IF

    argsStr$ = tiraCode$(ii)

    ' Clear array slot for next usage cycle to maintain a clean slate state
    tiraCmd(ii) = TC_INVALID

    FOR iClear = 0 TO 31
      args$(iClear) = ""
    NEXT

    ' Inline string parsing to split argsStr$ by comma, respecting quotes
    aCount = 0
    ix = 1
    aLen = LEN(argsStr$)
    currArg$ = ""
    inQuotes = 0

    DO WHILE ix <= aLen
      ch$ = MID$(argsStr$, ix, 1)

      IF ch$ = CHR$(34) THEN
        inQuotes = 1 - inQuotes
      END IF

      IF ch$ = "," AND inQuotes = 0 THEN
        args$(aCount) = LTRIM$(RTRIM$(currArg$))
        aCount = aCount + 1
        currArg$ = ""
      ELSE
        currArg$ = currArg$ + ch$
      END IF
      ix = ix + 1
    LOOP

    IF currArg$ <> "" THEN
      args$(aCount) = LTRIM$(RTRIM$(currArg$))
      aCount = aCount + 1
    END IF

    IF cmdNum = TC_LABEL THEN
      labelName$ = argsStr$
      firstChar$ = LEFT$(labelName$, 1)
      IF firstChar$ <> "@" THEN
        throwCompilerError "Internal labels must use @ prefix", ASIS, 0
        t.IsActive = 0
        EXIT SUB
      END IF

      ff = resolveSymbol(labelName$)
      IF ff = 1 THEN
        vIdx = returnedData2
        symbols(vIdx).DataType = TYPE_LABEL
        symbols(vIdx).Offset = stream.emitPos
        symbols(vIdx).alreadyParsed = 1
      END IF
    ELSE

      SELECT CASE cmdNum

        CASE TC_SET_SUB_OFFSET
          ' Compiler directive: Record stream.emitPos directly into the subs array at this exact moment in emission
          subIdx = VAL(args$(0))
          subs(subIdx).Offset = stream.emitPos

        CASE TC_MAIN_PROLOGUE
          stack.currentStackOffset = 8
          ff = updateStackAlignment
          allocSize = VAL(args$(0))
          IF allocSize > 0 THEN
            tasm_ProbeStack allocSize
          END IF

        CASE TC_ENTER_FRAME
          stack.currentStackOffset = 8
          ff = updateStackAlignment
          allocSize = VAL(args$(0))

          ' Standard x64 ABI Prologue: Set up RBP as a stable frame pointer
          opPushReg 5 ' RBP
          ff = opMov(OP_TYPE_REG, 5, OP_TYPE_REG, 4, 64) ' mov rbp, rsp

          ' Push non-volatile registers to conform to x64 ABI calling conventions
          opPushReg 3 ' RBX
          opPushReg 6 ' RSI
          opPushReg 7 ' RDI
          opPushReg 12 ' R12
          opPushReg 13 ' R13
          opPushReg 14 ' R14
          opPushReg 15 ' R15

          ' Allocate the local stack frame using safe OS guard page probing
          tasm_ProbeStack allocSize

          ' Store RSP (Register 4) into the provided TIRA tracking variable
          tasm_StoreOperand args$(1), 4, 0

        CASE TC_LEAVE_FRAME
          allocSize = VAL(args$(0))

          ' Deallocate the local stack frame
          IF allocSize > 0 THEN
            opAddRsp32 allocSize
          END IF

          ' Pop non-volatile registers in reverse order to conform to x64 ABI
          opPopReg 15 ' R15
          opPopReg 14 ' R14
          opPopReg 13 ' R13
          opPopReg 12 ' R12
          opPopReg 7 ' RDI
          opPopReg 6 ' RSI
          opPopReg 3 ' RBX

          ' Restore caller's RBP frame pointer
          emitByteCode &H5D
          stack.currentStackOffset = stack.currentStackOffset - 8
          ff = updateStackAlignment

          ' Return to caller
          opRet

        CASE TC_ABI_PROLOGUE
          allocSize = VAL(args$(0))

          ' Industry Standard: Set up RBP as the stable frame pointer
          opPushReg 5 ' RBP
          ff = opMov(OP_TYPE_REG, 5, OP_TYPE_REG, 4, 64) ' mov rbp, rsp

          ' Spill volatile ABI registers to their guaranteed shadow space
          ' Because RBP is our stable anchor, these offsets never change
          ff = opMov(OP_TYPE_MEM_RBP, 16, OP_TYPE_REG, 1, 64) ' RCX -> [rbp+16]
          ff = opMov(OP_TYPE_MEM_RBP, 24, OP_TYPE_REG, 2, 64) ' RDX -> [rbp+24]
          ff = opMov(OP_TYPE_MEM_RBP, 32, OP_TYPE_REG, 8, 64) ' R8  -> [rbp+32]
          ff = opMov(OP_TYPE_MEM_RBP, 40, OP_TYPE_REG, 9, 64) ' R9  -> [rbp+40]

          opPushReg 3 ' RBX

          ' Stack alignment math: 24 bytes pushed (RIP + RBP + RBX)
          ' allocSize must pad RSP so that (24 + allocSize) MOD 16 == 0
          ' Therefore, allocSize MOD 16 must equal 8
          remainder = allocSize MOD 16
          IF remainder <= 8 THEN
            allocSize = allocSize + (8 - remainder)
          ELSE
            allocSize = allocSize + (24 - remainder)
          END IF

          IF allocSize > 0 THEN
            opSubRsp32 allocSize
          END IF

          ' Reset generator's stack tracking for the new perfectly aligned runtime frame
          stack.currentStackOffset = 0
          ff = updateStackAlignment

        CASE TC_ABI_EPILOGUE
          allocSize = VAL(args$(0))

          ' Recalculate the exact padding to restore RSP cleanly
          remainder = allocSize MOD 16
          IF remainder <= 8 THEN
            allocSize = allocSize + (8 - remainder)
          ELSE
            allocSize = allocSize + (24 - remainder)
          END IF

          IF allocSize > 0 THEN
            opAddRsp32 allocSize
          END IF

          ' Temporarily restore stack tracking to reflect the two pushed registers (RBP, RBX)
          ' This prevents the compiler's underflow safety from triggering on the pops
          stack.currentStackOffset = 16
          ff = updateStackAlignment

          opPopReg 3 ' RBX

          emitByteCode &H5D
          stack.currentStackOffset = stack.currentStackOffset - 8
          ff = updateStackAlignment

          opRet

          ' Reset generator's stack tracking safely
          stack.currentStackOffset = 0
          ff = updateStackAlignment

        CASE TC_ABI_READ_ARG
          destStr$ = args$(0)
          argIdx = VAL(args$(1))

          ff = resolveSymbol(destStr$)
          IF ff = 0 THEN
            tira_Cancel
            EXIT SUB
          END IF
          destVIdx = returnedData2
          targetType = returnedData3

          ' Because we spilled all registers to the shadow space in the prologue, we can
          ' uniformly read every argument directly from the stack using the RBP anchor
          ' [rbp + 16] = Arg 1, [rbp + 24] = Arg 2, [rbp + 48] = Arg 5, etc.
          stackOffset = 8 + (argIdx * 8)

          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RBP, stackOffset, opMode)
            ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, opMode, destVIdx)
          ELSE
            ' Read the 64-bit argument from the stack into RAX
            ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RBP, stackOffset, 64)

            ' Write from RAX into the destination variable using its specific byte size
            SELECT CASE targetType
              CASE TYPE_BYTE, TYPE_UBYTE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 8, destVIdx)
              CASE TYPE_INTEGER, TYPE_UINTEGER
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 16, destVIdx)
              CASE TYPE_LONG, TYPE_ULONG
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, destVIdx)
              CASE TYPE_INTEGER64, TYPE_UINT64
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, destVIdx)
              CASE ELSE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, destVIdx)
            END SELECT
          END IF

        CASE TC_ABI_WRITE_RET
          srcStr$ = args$(0)
          ff = resolveSymbol(srcStr$)
          IF ff = 0 THEN
            tira_Cancel
            EXIT SUB
          END IF
          srcVIdx = returnedData2
          targetType = returnedData3

          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, opMode, srcVIdx)
          ELSE
            ' Read from the source variable into RAX using its specific byte size and sign extension rules
            SELECT CASE targetType
              CASE TYPE_BYTE: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVSX64_8, srcVIdx)
              CASE TYPE_UBYTE: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVZX64_8, srcVIdx)
              CASE TYPE_INTEGER: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVSX64_16, srcVIdx)
              CASE TYPE_UINTEGER: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVZX64_16, srcVIdx)
              CASE TYPE_LONG: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVSXD, srcVIdx)
              CASE TYPE_ULONG: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 32, srcVIdx)
              CASE TYPE_INTEGER64, TYPE_UINT64: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, srcVIdx)
              CASE ELSE: ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, srcVIdx)
            END SELECT
          END IF

        CASE TC_ASSIGN
          tasm_LoadOperand args$(1), 0
          isFloat1 = returnedData2
          tasm_StoreOperand args$(0), 0, isFloat1

        CASE TC_CAST
          tasm_DoCast args$(0), args$(1), args$(2)

        CASE TC_ADD, TC_SUB, TC_MUL, TC_DIV, TC_IDIV, TC_MOD, TC_AND, TC_OR, TC_POW, TC_CONCAT, TC_COMPARE
          tasm_DoMath cmdNum, args$(0), args$(1), args$(2)

        CASE TC_SHL, TC_SHR
          tasm_DoShift cmdNum, args$(0), args$(1), args$(2)

        CASE TC_NEG, TC_NOT
          tasm_DoUnary cmdNum, args$(0), args$(1)

        CASE TC_TEST
          src1Str$ = args$(0)
          src2Str$ = args$(1)

          tasm_LoadOperand src1Str$, 0
          isFloat1 = returnedData2
          tasm_LoadOperand src2Str$, 3
          isFloat2 = returnedData2

          IF isFloat1 > 0 THEN
            opModeFloat = MODE_SSE_DOUBLE:
            IF isFloat1 = 1 THEN opModeFloat = MODE_SSE_SINGLE
            ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opModeFloat)
          END IF

          IF isFloat2 > 0 THEN
            opModeFloat = MODE_SSE_DOUBLE
            IF isFloat2 = 1 THEN opModeFloat = MODE_SSE_SINGLE
            ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 3, OP_TYPE_REG, 3, opModeFloat)
          END IF

          ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)

        CASE TC_JCC
          condCodeStr$ = args$(0)
          targetLabel$ = args$(1)

          firstChar$ = LEFT$(targetLabel$, 1)
          IF firstChar$ <> "@" THEN
            throwCompilerErrorAndCancelTira "Internal jump targets must use @ prefix", ASIS, 0
            EXIT SUB
          END IF

          jmpType = JCC_JE
          SELECT CASE condCodeStr$

            CASE "JO", "O": jmpType = JCC_JO
            CASE "JNO", "NO": jmpType = JCC_JNO
            CASE "JE", "EQ": jmpType = JCC_JE
            CASE "JNE", "NE": jmpType = JCC_JNE
            CASE "JL", "LT": jmpType = JCC_JL
            CASE "JLE", "LE": jmpType = JCC_JLE
            CASE "JG", "GT": jmpType = JCC_JG
            CASE "JGE", "GE": jmpType = JCC_JGE
            CASE "JB", "B": jmpType = JCC_JB
            CASE "JBE", "BE": jmpType = JCC_JBE
            CASE "JA", "A": jmpType = JCC_JA
            CASE "JAE", "AE": jmpType = JCC_JAE

          END SELECT ' condCodeStr$

          ff = resolveSymbol(targetLabel$)
          IF ff = 1 THEN
            vIdx = returnedData2
            addPatch PATCH_GOTO, opJcc(jmpType, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx
          END IF
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            tira_Cancel
            EXIT SUB
          END IF

        CASE TC_JMP
          firstChar$ = LEFT$(args$(0), 1)
          IF firstChar$ <> "@" THEN
            throwCompilerErrorAndCancelTira "Internal jump targets must use @ prefix", ASIS, 0
            EXIT SUB
          END IF
          ff = resolveSymbol(args$(0))
          IF ff = 1 THEN
            vIdx = returnedData2
            addPatch PATCH_GOTO, opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx
          END IF
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            tira_Cancel
            EXIT SUB
          END IF

        CASE TC_JMP_USER
          ff = resolveSymbol(args$(0))
          IF ff = 1 THEN
            vIdx = returnedData2
            addPatch PATCH_GOTO, opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx
          END IF
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            tira_Cancel
            EXIT SUB
          END IF

        CASE TC_READ_MEM
          destStr$ = args$(0)
          ptrStr$ = args$(1)

          ff = resolveSymbol(destStr$)
          IF ff = 0 THEN
            tira_Cancel
            t.IsActive = 0
            EXIT SUB
          END IF
          destVIdx = returnedData2
          targetType = returnedData3

          tasm_LoadOperand ptrStr$, 10

          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, opMode)

            IF targetType = TYPE_SINGLE THEN
              isFloat1 = 1
            ELSE
              isFloat1 = 2
            END IF
          ELSE

            SELECT CASE targetType

              CASE TYPE_BYTE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, MODE_MOVSX64_8)
              CASE TYPE_UBYTE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, MODE_MOVZX64_8)
              CASE TYPE_INTEGER: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, MODE_MOVSX64_16)
              CASE TYPE_UINTEGER: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, MODE_MOVZX64_16)
              CASE TYPE_LONG: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, MODE_MOVSXD)
              CASE TYPE_ULONG, TYPE_SINGLE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, 32)
              CASE TYPE_INTEGER64, TYPE_UINT64: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, 64)
              CASE ELSE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 10, 64)

            END SELECT ' targetType

            isFloat1 = 0
          END IF

          tasm_StoreOperand destStr$, 0, isFloat1

        CASE TC_READ_MEM_OFFSET
          destStr$ = args$(0)
          ptrStr$ = args$(1)
          dispVal = VAL(args$(2))

          ' Dynamically expands memory size to 32-bit for safety when the value exceeds signed 8-bit limits
          IF dispVal >= -128 AND dispVal <= 127 THEN
            memOpTypeR = OP_TYPE_MEM_REG_DISP8
          ELSE
            memOpTypeR = OP_TYPE_MEM_REG_DISP32
          END IF

          ff = resolveSymbol(destStr$)
          IF ff = 0 THEN
            tira_Cancel
            EXIT SUB
          END IF
          destVIdx = returnedData2
          targetType = returnedData3

          tasm_LoadOperand ptrStr$, 10

          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_MOV, OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), opMode)

            IF targetType = TYPE_SINGLE THEN
              isFloat1 = 1
            ELSE
              isFloat1 = 2
            END IF
          ELSE

            SELECT CASE targetType

              CASE TYPE_BYTE: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), MODE_MOVSX64_8)
              CASE TYPE_UBYTE: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), MODE_MOVZX64_8)
              CASE TYPE_INTEGER: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), MODE_MOVSX64_16)
              CASE TYPE_UINTEGER: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), MODE_MOVZX64_16)
              CASE TYPE_LONG: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), MODE_MOVSXD)
              CASE TYPE_ULONG, TYPE_SINGLE: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), 32)
              CASE TYPE_INTEGER64, TYPE_UINT64: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), 64)
              CASE ELSE: ff = opMov(OP_TYPE_REG, 0, memOpTypeR, 10 + (dispVal * 256), 64)

            END SELECT ' targetType

            isFloat1 = 0
          END IF

          tasm_StoreOperand destStr$, 0, isFloat1

        CASE TC_WRITE_MEM
          destAddrStr$ = args$(0)
          srcValStr$ = args$(1)
          sizeMode$ = args$(2)

          tasm_LoadOperand destAddrStr$, 10
          tasm_LoadOperand srcValStr$, 0
          isFloat2 = returnedData2

          IF sizeMode$ = "SINGLE" OR sizeMode$ = "DOUBLE" THEN
            IF isFloat2 = 0 THEN
              ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
              isFloat2 = 2
            END IF
            opMode = MODE_SSE_DOUBLE
            IF sizeMode$ = "SINGLE" THEN opMode = MODE_SSE_SINGLE

            IF isFloat2 = 2 AND sizeMode$ = "SINGLE" THEN
              ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
            END IF
            IF isFloat2 = 1 AND sizeMode$ = "DOUBLE" THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
            END IF

            ff = opSSE(SSE_MOV, OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 0, opMode)
          ELSE
            IF isFloat2 > 0 THEN
              opMode = MODE_SSE_DOUBLE
              IF isFloat2 = 1 THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF

            SELECT CASE sizeMode$

              CASE "1": ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 0, 8)
              CASE "2": ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 0, 16)
              CASE "4": ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 0, 32)
              CASE "8": ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 0, 64)

            END SELECT ' sizeMode$

          END IF

        CASE TC_WRITE_MEM_OFFSET
          destPtrStr$ = args$(0)
          dispVal = VAL(args$(1))
          srcValStr$ = args$(2)
          sizeMode$ = args$(3)

          ' Dynamically expands memory size to 32-bit for safety when the value exceeds signed 8-bit limits
          IF dispVal >= -128 AND dispVal <= 127 THEN
            memOpTypeW = OP_TYPE_MEM_REG_DISP8
          ELSE
            memOpTypeW = OP_TYPE_MEM_REG_DISP32
          END IF

          tasm_LoadOperand destPtrStr$, 10
          tasm_LoadOperand srcValStr$, 0
          isFloat2 = returnedData2

          IF sizeMode$ = "SINGLE" OR sizeMode$ = "DOUBLE" THEN
            IF isFloat2 = 0 THEN
              ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
              isFloat2 = 2
            END IF
            opMode = MODE_SSE_DOUBLE
            IF sizeMode$ = "SINGLE" THEN opMode = MODE_SSE_SINGLE

            IF isFloat2 = 2 AND sizeMode$ = "SINGLE" THEN
              ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
            END IF
            IF isFloat2 = 1 AND sizeMode$ = "DOUBLE" THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
            END IF

            ff = opSSE(SSE_MOV, memOpTypeW, 10 + (dispVal * 256), OP_TYPE_REG, 0, opMode)
          ELSE
            IF isFloat2 > 0 THEN
              opMode = MODE_SSE_DOUBLE
              IF isFloat2 = 1 THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF

            SELECT CASE sizeMode$

              CASE "1": ff = opMov(memOpTypeW, 10 + (dispVal * 256), OP_TYPE_REG, 0, 8)
              CASE "2": ff = opMov(memOpTypeW, 10 + (dispVal * 256), OP_TYPE_REG, 0, 16)
              CASE "4": ff = opMov(memOpTypeW, 10 + (dispVal * 256), OP_TYPE_REG, 0, 32)
              CASE "8": ff = opMov(memOpTypeW, 10 + (dispVal * 256), OP_TYPE_REG, 0, 64)

            END SELECT ' sizeMode$

          END IF

        CASE TC_SWAP_MEM
          tasm_DoSwap args$(0), args$(1), args$(2)

        CASE TC_MEMCPY
          destAddrStr$ = args$(0)
          srcAddrStr$ = args$(1)
          lenStr$ = args$(2)

          opPushReg 7 ' Protect ABI non-volatile RDI
          opPushReg 6 ' Protect ABI non-volatile RSI

          tasm_LoadOperand destAddrStr$, 7 ' Load into RDI
          tasm_LoadOperand srcAddrStr$, 6 ' Load into RSI

          opPushReg 1 ' Protect volatile RCX
          tasm_LoadOperand lenStr$, 1 ' Load into RCX

          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          jmpSkipMemCpy = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
          opFlag FLAG_CLD
          opString STR_MOVS, REP_REP, 8
          patch8 jmpSkipMemCpy

          opPopReg 1
          opPopReg 6
          opPopReg 7

        CASE TC_MEMSET
          destAddrStr$ = args$(0)
          valStr$ = args$(1)
          lenStr$ = args$(2)

          opPushReg 7 ' Protect ABI non-volatile RDI

          tasm_LoadOperand destAddrStr$, 7 ' Load into RDI
          tasm_LoadOperand valStr$, 0 ' Load into RAX

          opPushReg 1 ' Protect volatile RCX
          tasm_LoadOperand lenStr$, 1 ' Load into RCX

          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          jmpSkipMemSet = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
          opFlag FLAG_CLD
          opString STR_STOS, REP_REP, 8
          patch8 jmpSkipMemSet

          opPopReg 1
          opPopReg 7

        CASE TC_JMP_COND
          ff = tasmEndHelper_JMP_COND(args$(0), args$(1), args$(2), args$(3))
          IF ff = 0 THEN
            tira_Cancel
            EXIT SUB
          END IF

        CASE TC_GET_RET
          destStr$ = args$(0)
          ff = resolveSymbol(destStr$)
          IF ff = 0 THEN
            tira_Cancel
            EXIT SUB
          END IF
          destIdx = returnedData2
          targetType = returnedData3

          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, opMode, destIdx)
          ELSE

            SELECT CASE targetType

              CASE TYPE_BYTE, TYPE_UBYTE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 8, destIdx)
              CASE TYPE_INTEGER, TYPE_UINTEGER
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 16, destIdx)
              CASE TYPE_LONG, TYPE_ULONG
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, destIdx)
              CASE TYPE_INTEGER64, TYPE_UINT64
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, destIdx)
              CASE TYPE_STRING
                IF LEFT$(symbols(destIdx).RecordName, 1) = "~" THEN
                  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, destIdx)
                ELSE
                  opPushReg 1
                  opPushReg 2

                  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
                  ff = genSymbolRouteLea(1, destIdx)

                  opPushReg 8
                  opPushReg 9
                  opPushReg 10
                  opPushReg 11

                  pushedDummy = 0
                  IF updateStackAlignment = 0 THEN
                    opPushReg 13
                    pushedDummy = 1
                  END IF

                  ' Allocate 32 bytes shadow space to prevent prologue stack corruption
                  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
                  stack.currentStackOffset = stack.currentStackOffset + 32
                  ff = updateStackAlignment

                  rtIsUsed(RT_STR_ASSIGN) = 1
                  addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN
                  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                    tira_Cancel
                    EXIT SUB
                  END IF

                  ' Restore shadow space
                  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
                  stack.currentStackOffset = stack.currentStackOffset - 32
                  ff = updateStackAlignment

                  IF pushedDummy = 1 THEN
                    opPopReg 13
                  END IF

                  opPopReg 11
                  opPopReg 10
                  opPopReg 9
                  opPopReg 8

                  opPopReg 2
                  opPopReg 1
                END IF
              CASE ELSE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, destIdx)

            END SELECT ' targetType

          END IF

        CASE TC_GET_RSP
          destStr$ = args$(0)
          ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 4, 64)
          tasm_StoreOperand destStr$, 0, 0

        CASE TC_CALL
          funcName$ = args$(0)
          argCount = VAL(args$(1))

          IF argCount > 16 THEN
            throwCompilerErrorAndCancelTira "TIRA_CALL WITH > 16 ARGS NOT SUPPORTED", ASIS, 0
            EXIT SUB
          END IF

          DIM isIAT AS LONG
          DIM isRT AS LONG
          isIAT = 0
          isRT = 0
          IF LEFT$(funcName$, 4) = "IAT_" THEN isIAT = 1
          IF LEFT$(funcName$, 3) = "RT_" THEN isRT = 1

          allocSize = 32 ' ALWAYS allocate shadow space for x64 ABI compliance
          IF argCount > 4 THEN
            allocSize = allocSize + ((argCount - 4) * 8)
          END IF

          ' Standardize payload strictly for alignment guarantee
          IF (allocSize MOD 16) <> 0 THEN
            allocSize = allocSize + 8
          END IF

          pushedDummy = 0
          IF updateStackAlignment = 0 THEN
            opPushReg 13
            pushedDummy = 1
          END IF

          ' Allocate shadow space and standard stack argument routing array
          IF allocSize > 0 THEN
            ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, allocSize, 64)
            stack.currentStackOffset = stack.currentStackOffset + allocSize
            ff = updateStackAlignment
          END IF

          ' Standard Win64 Calling Convention Routing Loop
          FOR iArg = 0 TO argCount - 1
            ' First load the operand into RAX or XMM0 blindly
            tasm_LoadOperand args$(2 + iArg), 0
            isFloat1 = returnedData2

            IF isFloat1 > 0 THEN
              ' Route to standard XMM register block or Stack
              opMode = MODE_SSE_DOUBLE
              IF isFloat1 = 1 THEN opMode = MODE_SSE_SINGLE

              SELECT CASE iArg

                CASE 0
                  ' already in xmm0
                CASE 1
                  ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 0, opMode)
                CASE 2
                  ff = opSSE(SSE_MOV, OP_TYPE_REG, 2, OP_TYPE_REG, 0, opMode)
                CASE 3
                  ff = opSSE(SSE_MOV, OP_TYPE_REG, 3, OP_TYPE_REG, 0, opMode)
                CASE ELSE
                  ' ALWAYS use the absolute stack index now, no need to separate IAT and internal
                  ff = opSSE(SSE_MOV, OP_TYPE_MEM_RSP, 32 + ((iArg - 4) * 8), OP_TYPE_REG, 0, opMode)

              END SELECT ' iArg

              '''' VARARGS mirroring
              ' The Windows x64 ABI requires that varargs functions (like sprintf)
              ' receive float values in BOTH the XMM register and the corresponding GPR
              IF iArg < 4 THEN
                ' Copy XMM0 into RAX without converting (bitwise copy)
                ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)

                ' Route RAX to the correct General Purpose Register
                SELECT CASE iArg

                  CASE 0
                    ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
                  CASE 1
                    ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
                  CASE 2
                    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 0, 64)
                  CASE 3
                    ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 0, 64)

                END SELECT ' iArg

              END IF

            ELSE
              ' Route to standard GPR block (RCX, RDX, R8, R9) or Stack

              SELECT CASE iArg

                CASE 0
                  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
                CASE 1
                  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
                CASE 2
                  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 0, 64)
                CASE 3
                  ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 0, 64)
                CASE ELSE
                  ff = opMov(OP_TYPE_MEM_RSP, 32 + ((iArg - 4) * 8), OP_TYPE_REG, 0, 64)

              END SELECT ' iArg

            END IF
          NEXT

          ' Resolve Subroutine offset dynamically
          IF isRT = 1 THEN
            DIM rtOffset AS LONG
            rtOffset = retRtOffsetByName(funcName$)

            IF rtOffset = 0 THEN
              throwCompilerErrorAndCancelTira "RUNTIME HELPER NOT FOUND IN TIRA_CALL: " + funcName$, ASIS, 0
              EXIT SUB
            END IF

            rtIsUsed(rtOffset) = 1

            addPatch PATCH_RT, opCall(0, CALLMODE_REL32), rtOffset
            IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
              t.IsActive = 0
              EXIT SUB
            END IF

          ELSE
            IF isIAT = 1 THEN
              DIM iatConst AS LONG
              iatConst = retIatConstByName(funcName$, 1)

              IF iatConst = IAT_INVALID THEN
                throwCompilerErrorAndCancelTira "INVALID IAT CALL: " + funcName$, ASIS, 0
                EXIT SUB
              END IF

              ' Directly run an unprotected opCall because TIRA_CALL intrinsically guarantees stack alignments
              ff = opCall(iatConst, CALLMODE_IAT)
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                tira_Cancel
                EXIT SUB
              END IF

            ELSE
              ' User SUB mapping
              ff = findSubIndex(funcName$)
              IF ff = 1 THEN
                addPatch PATCH_CALL, opCall(0, CALLMODE_REL32), returnedData2
              ELSE
                throwCompilerErrorAndCancelTira "SUB NOT FOUND IN TIRA_CALL: " + funcName$, ASIS, 0
                EXIT SUB
              END IF

              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                tira_Cancel
                EXIT SUB
              END IF
            END IF
          END IF

          ' Restore stack footprint offsets safely
          IF allocSize > 0 THEN
            ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, allocSize, 64)
            stack.currentStackOffset = stack.currentStackOffset - allocSize
            ff = updateStackAlignment
          END IF
          IF pushedDummy = 1 THEN
            opPopReg 13
          END IF

        CASE TC_XCHG
          destAddrStr$ = args$(0)
          srcValStr$ = args$(1)
          sizeMode$ = args$(2)

          tasm_LoadOperand srcValStr$, 0
          ff = resolveSymbol(destAddrStr$)
          IF ff = 1 THEN
            vIdx = returnedData2
            ff = genSymbolRouteLea(10, vIdx)

            IF sizeMode$ = "4" THEN
              emitByteCode &H41: emitByteCode &H87: emitByteCode &H02
            ELSE
              IF sizeMode$ = "8" THEN
                emitByteCode &H49: emitByteCode &H87: emitByteCode &H02
              ELSE
                emitByteCode &H41: emitByteCode &H87: emitByteCode &H02
              END IF
            END IF
            tasm_StoreOperand srcValStr$, 0, 0
          ELSE
            throwCompilerErrorAndCancelTira "SYMBOL NOT FOUND IN XCHG", ASIS, 0
            EXIT SUB
          END IF

        CASE TC_ADDRESS_OF
          IF LEFT$(args$(1), 3) = "RT_" THEN
            rtAddrOffset = retRtOffsetByName(args$(1))

            IF rtAddrOffset = 0 THEN
              throwCompilerErrorAndCancelTira "RUNTIME HELPER NOT FOUND IN TC_ADDRESS_OF: " + args$(1), ASIS, 0
              EXIT SUB
            END IF

            rtIsUsed(rtAddrOffset) = 1

            addPatch PATCH_RT, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), rtAddrOffset
            IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
              tira_Cancel
              EXIT SUB
            END IF

            tasm_StoreOperand args$(0), 0, 0
          ELSE
            ' Resolve the symbol index of the source variable
            ff = resolveSymbol(args$(1))
            IF ff = 1 THEN
              srcVIdx = returnedData2

              ' Generate the Load Effective Address (LEA) into RAX (Register 0)
              ff = genSymbolRouteLea(0, srcVIdx)

              ' Store the calculated address from RAX into the destination variable
              tasm_StoreOperand args$(0), 0, 0
            ELSE
              throwCompilerErrorAndCancelTira "SYMBOL NOT FOUND", ASIS, 0
              EXIT SUB
            END IF
          END IF

        CASE TC_RESUME
          ff = resolveSymbol("!G_SYS_LAST_ERR_PTR")
          IF ff = 1 THEN
            ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, returnedData2)
          END IF
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            tira_Cancel
            EXIT SUB
          END IF
          emitByteCode &HFF: emitByteCode &HE0

        CASE TC_LEA_SIB
          destStr$ = args$(0)
          baseStr$ = args$(1)
          idxStr$ = args$(2)
          scaleVal$ = args$(3)

          tasm_LoadOperand baseStr$, 10 ' Load Base into R10
          tasm_LoadOperand idxStr$, 11 ' Load Index into R11

          sVal = VAL(scaleVal$)
          ' opLea_SIB(destReg, baseReg, indexReg, scaleVal, dispVal, opSize)
          ff = opLea_SIB(0, 10, 11, sVal, 0, 64) ' RAX = R10 + R11*scale

          tasm_StoreOperand destStr$, 0, 0 ' Store RAX back to dest

        CASE TC_BOUNDS_CHECK
          arrName$ = args$(0)
          xVar$ = args$(1)
          yVar$ = args$(2)

          ff = resolveSymbol("@NATIVE_BOUNDS_HANDLER")
          IF ff = 1 THEN boundsVIdx = returnedData2

          tasm_LoadOperand xVar$, 0
          tasm_LoadOperand "!G_SYS_" + arrName$ + "_AX_VAL", 3
          ' Speed boost optimization: Using unsigned jump (JAE) checks both < 0 and >= max limit simultaneously
          ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
          addPatch PATCH_GOTO, opJcc(JCC_JAE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), boundsVIdx

          IF yVar$ <> "" AND yVar$ <> "0" THEN
            tasm_LoadOperand yVar$, 0
            tasm_LoadOperand "!G_SYS_" + arrName$ + "_AY_VAL", 3
            ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
            addPatch PATCH_GOTO, opJcc(JCC_JAE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), boundsVIdx
          END IF

        CASE TC_REDIM
          ' Redim memory reallocation is abstracted cleanly into frontend heap commands

        CASE TC_JMP_DYN
          tasm_LoadOperand args$(0), 0
          emitByteCode &HFF: emitByteCode &HE0

        CASE ELSE
          throwCompilerErrorAndCancelTira "TIRA COMMAND NOT IMPLEMENTED IN BACKEND", ASIS, 0
          EXIT SUB

      END SELECT ' cmdNum

    END IF
  NEXT

  t.LineCount = 0 ' Reset for another TIRA round, triggered by tira Start function
  t.IsActive = 0

END SUB ' tira_EndAndProcess

''''''''''''''''''''''''
SUB tira_Start

  IF t.IsActive <> 0 THEN
    throwCompilerError "TIRA QUEUE ALREADY ACTIVE", ASIS, 0
    EXIT SUB
  END IF

  t.IsActive = 1

  ' Initializes the localized 3AC queue for a single BASIC statement
  t.LineCount = 0

  ' Reset the ephemeral TIRA variable counter for this specific statement block
  t.TempCounter = 0

END SUB ' tira_Start

''''''''''''''''''''''''
FUNCTION tiraAllocTempMem$ (sizeStr$)

  tiraCheckActive ("tiraAllocTempMem$")

  dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign dataPtr$, "!G_MEM_TEMP_HEAP_PTR"
  tiraOp TC_SUB, dataPtr$, dataPtr$, sizeStr$
  tiraAssign "!G_MEM_TEMP_HEAP_PTR", dataPtr$

  tiraAllocTempMem$ = dataPtr$

END FUNCTION ' tiraAllocTempMem$

''''''''''''''''''''''''
SUB tiraAssign (dest$, src$)

  tiraCheckActive ("tiraAssign")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_ASSIGN
  tiraCode$(t.LineCount) = dest$ + ", " + src$
  t.LineCount = t.LineCount + 1

END SUB ' tiraAssign

''''''''''''''''''''''''
SUB tiraBoundsCheck (arrName$, xVar$, yVar$)

  tiraCheckActive ("tiraBoundsCheck")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_BOUNDS_CHECK
  tiraCode$(t.LineCount) = arrName$ + ", " + xVar$ + ", " + yVar$
  t.LineCount = t.LineCount + 1

END SUB ' tiraBoundsCheck

''''''''''''''''''''''''
SUB tiraBuildStringDescriptor (descBasePtrVar$, dataPtrVar$, strLenVar$, flagValStr$)

  tiraCheckActive ("tiraBuildStringDescriptor")
  IF tiraLineCheck THEN EXIT SUB

  tiraWriteMem descBasePtrVar$, dataPtrVar$, "8"

  lenPtrD$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, lenPtrD$, descBasePtrVar$, "8"
  tiraWriteMem lenPtrD$, strLenVar$, "8"

  flagPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, flagPtr$, descBasePtrVar$, "16"
  tiraWriteMem flagPtr$, flagValStr$, "8"

END SUB ' tiraBuildStringDescriptor

''''''''''''''''''''''''
SUB tiraBuildStylePlot (x$, y$)

  tiraCheckActive ("tiraBuildStylePlot")

  styleBit$ = tiraDimVar$("T", TYPE_LONG)
  styleHigh$ = tiraDimVar$("T", TYPE_LONG)
  styleLow$ = tiraDimVar$("T", TYPE_LONG)

  lblSkipPlot$ = tiraLabelCreateNew$("SKIP_PLOT")

  tiraOp TC_AND, styleBit$, "!G_GFX_STYLE_VAL", "32768"
  tiraJmpCond "JE", styleBit$, "0", lblSkipPlot$

  tiraCall "RT_PLOT_PIXEL", 3, x$ + ", " + y$ + ", !G_GFX_COLOR_VAL"

  tiraLabel lblSkipPlot$

  ' Emulate a 16-bit ROL command purely using TIRA math commands
  tiraOp TC_MUL, styleHigh$, "!G_GFX_STYLE_VAL", "2"
  tiraOp TC_AND, styleHigh$, styleHigh$, "65535"
  tiraOp TC_DIV, styleLow$, "!G_GFX_STYLE_VAL", "32768"
  tiraOp TC_AND, styleLow$, styleLow$, "1"
  tiraOp TC_OR, "!G_GFX_STYLE_VAL", styleHigh$, styleLow$

END SUB ' tiraBuildStylePlot

''''''''''''''''''''''''
SUB tiraCall (funcName$, argCount AS LONG, argList$)

  ' tira_EndAndProcess automatically handles the Windows x64 ABI stack
  ' alignment and shadow space allocation for all TIRA_CALLs. It detects "IAT_"
  ' prefixes to know when to allocate the mandatory 32-byte shadow space for
  ' external Windows APIs, and strips it away for "RT_" and internal SUBs
  ' to keep the stack lean, while always ensuring strict 16-byte alignment.

  tiraCheckActive ("tiraCall")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_CALL

  IF argCount > 0 THEN
    tiraCode$(t.LineCount) = funcName$ + ", " + LTRIM$(RTRIM$(STR$(argCount))) + ", " + argList$
  ELSE
    tiraCode$(t.LineCount) = funcName$ + ", 0"
  END IF

  t.LineCount = t.LineCount + 1

END SUB ' tiraCall

''''''''''''''''''''''''
SUB tiraCheckActive (callerName$)

  IF t.IsActive <> 1 THEN
    throwCompilerError callerName$ + ": TIRA NOT VALUE 1, NO tira_Start CALL", ASIS, 0
  END IF

END SUB ' tiraCheckActive

''''''''''''''''''''''''
SUB tiraClamp (varToClamp$, minStr$, maxStr$)

  tiraCheckActive ("tiraClamp")
  IF tiraLineCheck THEN EXIT SUB

  IF minStr$ <> "" THEN
    skipMinLbl$ = tiraLabelCreateNew$("CLAMP_MIN")
    tiraJmpCond "JGE", varToClamp$, minStr$, skipMinLbl$
    tiraAssign varToClamp$, minStr$
    tiraLabel skipMinLbl$
  END IF

  IF maxStr$ <> "" THEN
    skipMaxLbl$ = tiraLabelCreateNew$("CLAMP_MAX")
    tiraJmpCond "JLE", varToClamp$, maxStr$, skipMaxLbl$
    tiraAssign varToClamp$, maxStr$
    tiraLabel skipMaxLbl$
  END IF

END SUB ' tiraClamp

''''''''''''''''''''''''
FUNCTION tiraDimVar$ (baseName$, wDataType AS LONG)

  tiraCheckActive ("tiraDimVar$")

  DIM vIdx AS LONG
  DIM varSize AS LONG
  DIM remainder AS LONG

  SELECT CASE wDataType

    CASE TYPE_STRING: typePrefix$ = "TSTR_"
    CASE TYPE_SINGLE: typePrefix$ = "TSNG_"
    CASE TYPE_DOUBLE: typePrefix$ = "TDBL_"
    CASE TYPE_BYTE: typePrefix$ = "TBYT_"
    CASE TYPE_UBYTE: typePrefix$ = "TUBY_"
    CASE TYPE_INTEGER: typePrefix$ = "TINT_"
    CASE TYPE_UINTEGER: typePrefix$ = "TUIN_"
    CASE TYPE_LONG: typePrefix$ = "TLNG_"
    CASE TYPE_ULONG: typePrefix$ = "TULN_"
    CASE TYPE_INTEGER64: typePrefix$ = "TI64_"
    CASE TYPE_UINT64: typePrefix$ = "TU64_"
    CASE TYPE_UDT: typePrefix$ = "TUDT_"
    CASE ELSE: typePrefix$ = "TUNK_"

  END SELECT ' wDataType

  ' Creates a highly readable, SSA-safe ephemeral variable name strictly bound to its datatype
  ' Segregate Runtime Helper variables into their own namespace to prevent corrupting User Code variables
  IF isCompilingRT = 1 THEN
    tempName$ = "~RT_" + typePrefix$ + baseName$ + "_" + LTRIM$(RTRIM$(STR$(t.TempCounter)))
  ELSE
    tempName$ = "~" + typePrefix$ + baseName$ + "_" + LTRIM$(RTRIM$(STR$(t.TempCounter)))
  END IF
  t.TempCounter = t.TempCounter + 1

  ff = resolveSymbol(tempName$)
  IF ff = 1 THEN
    vIdx = returnedData2
    symbols(vIdx).DataType = wDataType

    ' Automated Local Routing for Runtime Helpers
    IF isCompilingRT = 1 THEN
      symbols(vIdx).IsLocal = LOCAL_ABSOLUTE

      varSize = 8 ' Default fallback
      SELECT CASE wDataType
        CASE TYPE_BYTE, TYPE_UBYTE: varSize = 1
        CASE TYPE_INTEGER, TYPE_UINTEGER: varSize = 2
        CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: varSize = 4
        CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE, TYPE_STRING: varSize = 8
        CASE TYPE_UDT: varSize = udts(symbols(vIdx).UDTIndex).TotalSize
      END SELECT

      ' Pad the size to an 8-byte boundary to guarantee stack alignment
      remainder = varSize MOD 8
      IF remainder <> 0 THEN varSize = varSize + (8 - remainder)

      rtFrameSize = rtFrameSize + varSize
      ' -8 offset accounts for the pushed RBX register in TC_ABI_PROLOGUE
      symbols(vIdx).LocalOffset = -8 - rtFrameSize
    END IF
  END IF

  tiraDimVar$ = tempName$

END FUNCTION ' tiraDimVar$

''''''''''''''''''''''''
SUB tiraEnsureStringAlloc (descPtrVar$, targetAddrVar$)

  tiraCheckActive ("tiraEnsureStringAlloc")
  IF tiraLineCheck THEN EXIT SUB

  skipNullLbl$ = tiraLabelCreateNew$("SKIP_NULL")
  tiraJmpCond "JNE", descPtrVar$, "0", skipNullLbl$

  tiraCall "IAT_HEAPALLOC", 3, "!G_MEM_PROCESS_HEAP_PTR, 8, 24"
  tiraNew TC_GET_RET, descPtrVar$
  tiraWriteMem targetAddrVar$, descPtrVar$, "8"

  tiraLabel skipNullLbl$

END SUB ' tiraEnsureStringAlloc

''''''''''''''''''''''''
FUNCTION tiraForceInt$ (srcVar$)

  tiraCheckActive ("tiraForceInt$")

  DIM vIdx AS LONG
  DIM dt AS LONG

  ff = resolveSymbol(srcVar$)
  IF ff = 1 THEN
    vIdx = returnedData2
    dt = returnedData3

    ' If the virtual register holds a float, we must create a new integer temp
    ' register and explicitly cast it to force a TIRA conversion in the scheduler
    IF dt = TYPE_SINGLE OR dt = TYPE_DOUBLE THEN
      resVar$ = tiraDimVar$("T", TYPE_LONG)
      tiraOp TC_CAST, resVar$, srcVar$, LTRIM$(STR$(TYPE_LONG))
      tiraForceInt$ = resVar$
    ELSE
      tiraForceInt$ = srcVar$
    END IF
  ELSE
    tiraForceInt$ = srcVar$
  END IF

END FUNCTION ' tiraForceInt$

''''''''''''''''''''''''
FUNCTION tiraFrontendCalcAddress$ (vName$, xVar$, yVar$, udtOffset AS LONG)

  tiraCheckActive ("tiraFrontendCalcAddress$")
  IF tiraLineCheck THEN EXIT FUNCTION

  DIM vIdx AS LONG
  DIM vDataType AS LONG
  DIM elemSize AS LONG
  DIM dt AS LONG
  DIM fixedLen AS LONG
  DIM actualName AS STRING

  ff = resolveSymbol(vName$)
  IF ff = 0 THEN
    tiraFrontendCalcAddress$ = ""
    EXIT FUNCTION
  END IF
  vIdx = returnedData2
  vDataType = returnedData3

  ' Fix: Use the canonical record name from the symbol table to prevent
  ' suffix-stripping from misaligning the bounds checking variables (!ARR_AX)
  actualName$ = RTRIM$(symbols(vIdx).RecordName)

  baseAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)

  IF symbols(vIdx).IsArray = 2 THEN
    tiraNew TC_READ_MEM, baseAddrVar$ + ", " + actualName$
  ELSE
    tiraOp TC_ADDRESS_OF, baseAddrVar$, actualName$, ""
  END IF

  offsetVar$ = ""
  IF xVar$ <> "" THEN
    offsetVar$ = xVar$
    IF yVar$ <> "" THEN
      axVar$ = "!G_SYS_" + actualName$ + "_AX_VAL"
      yOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_MUL, yOffset$, yVar$, axVar$
      combinedOffset$ = tiraDimVar$("T", TYPE_INTEGER64)

      ' Ensure strict 64-bit extension for pointer scale mapping
      safeX$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_CAST, safeX$, offsetVar$, LTRIM$(STR$(TYPE_INTEGER64))

      tiraOp TC_ADD, combinedOffset$, safeX$, yOffset$
      offsetVar$ = combinedOffset$
    END IF

    dt = vDataType
    elemSize = 8

    SELECT CASE dt

      CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
      CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
      CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
      CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
      CASE TYPE_STRING
        fixedLen = retFixedStringLength(vIdx)
        IF fixedLen > 0 THEN
          elemSize = fixedLen
        ELSE
          elemSize = 8
        END IF
      CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize

    END SELECT ' dt

  END IF

  finalAddr$ = baseAddrVar$
  IF offsetVar$ <> "" THEN
    tiraBoundsCheck actualName$, xVar$, yVar$

    IF elemSize = 1 OR elemSize = 2 OR elemSize = 4 OR elemSize = 8 THEN
      ' Fast Path: Hardware Array Scaling (TC_LEA_SIB)
      safeFinalOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_CAST, safeFinalOffset$, offsetVar$, LTRIM$(STR$(TYPE_INTEGER64))

      newAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraLeaSIB newAddr$, finalAddr$, safeFinalOffset$, LTRIM$(RTRIM$(STR$(elemSize)))
      finalAddr$ = newAddr$
    ELSE
      ' Slow Path: Fallback to TC_MUL and TC_ADD
      safeOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_CAST, safeOffset$, offsetVar$, LTRIM$(STR$(TYPE_INTEGER64))

      byteOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_MUL, byteOffset$, safeOffset$, LTRIM$(RTRIM$(STR$(elemSize)))

      newAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_ADD, newAddr$, finalAddr$, byteOffset$
      finalAddr$ = newAddr$
    END IF
  END IF

  IF udtOffset > 0 THEN
    newAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, newAddr$, finalAddr$, LTRIM$(RTRIM$(STR$(udtOffset)))
    finalAddr$ = newAddr$
  END IF

  tiraFrontendCalcAddress$ = finalAddr$

END FUNCTION ' tiraFrontendCalcAddress$

''''''''''''''''''''''''
FUNCTION tiraGetPrecedence (opVal AS LONG)

  tiraCheckActive ("tiraGetPrecedence")

  DIM precLevel AS LONG

  SELECT CASE opVal

    CASE TOK_OP_UNARY_MINUS, TOK_OP_UNARY_NOT
      precLevel = 7
    CASE TOK_OP_POW
      precLevel = 6
    CASE TOK_OP_MUL, TOK_OP_DIV, TOK_OP_IDIV
      precLevel = 5
    CASE TOK_OP_PLUS, TOK_OP_MINUS
      precLevel = 4
    CASE TOK_OP_EQUAL, TOK_OP_LESS, TOK_OP_GREATER, TOK_OP_LESS_EQUAL, TOK_OP_GREATER_EQUAL, TOK_OP_NOT_EQUAL
      precLevel = 3
    CASE TOK_AND, TOK_OR
      precLevel = 2
    CASE ELSE
      precLevel = 0

  END SELECT ' opVal

  tiraGetPrecedence = precLevel

END FUNCTION ' tiraGetPrecedence

''''''''''''''''''''''''
FUNCTION tiraGetStringData$ (rPassDesc$)

  tiraCheckActive ("tiraGetPrecedence")

  dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_READ_MEM, dataPtr$ + ", " + rPassDesc$
  tiraGetStringData$ = dataPtr$

END FUNCTION ' tiraGetStringData$

''''''''''''''''''''''''
FUNCTION tiraGetStringLen$ (rPassDesc$)

  strLen$ = tiraDimVar$("T", TYPE_LONG)
  tiraNew TC_READ_MEM_OFFSET, strLen$ + ", " + rPassDesc$ + ", 8"
  tiraGetStringLen$ = strLen$

END FUNCTION ' tiraGetStringLen$

''''''''''''''''''''''''
SUB tiraInjectPendingDisplayFlush

  tiraCheckActive ("tiraInjectPendingDisplayFlush")
  IF tiraLineCheck THEN EXIT SUB

  tiraCall "RT_AUTODISPLAY_CHECK", 0, ""

END SUB ' tiraInjectPendingDisplayFlush

''''''''''''''''''''''''
SUB tiraJmp (labelName$)

  tiraCheckActive ("tiraJmp")
  IF tiraLineCheck THEN EXIT SUB

  firstChar$ = LEFT$(labelName$, 1)

  IF firstChar$ <> "@" THEN
    throwCompilerError "Internal jump targets must use @ prefix", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_JMP
  tiraCode$(t.LineCount) = labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraJmp

''''''''''''''''''''''''
SUB tiraJmpCond (cond$, src1$, src2$, labelName$)

  tiraCheckActive ("tiraJmpCond")
  IF tiraLineCheck THEN EXIT SUB

  firstChar$ = LEFT$(labelName$, 1)

  IF firstChar$ <> "@" THEN
    throwCompilerError "Internal jump targets must use @ prefix", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_JMP_COND
  tiraCode$(t.LineCount) = cond$ + ", " + src1$ + ", " + src2$ + ", " + labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraJmpCond

''''''''''''''''''''''''
SUB tiraJmpUser (labelName$)

  tiraCheckActive ("tiraJmpUser")
  IF tiraLineCheck THEN EXIT SUB

  IF LEFT$(labelName$, 1) <> "%" THEN
    throwCompilerError "User jump targets must use % prefix", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_JMP_USER
  tiraCode$(t.LineCount) = labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraJmpUser

''''''''''''''''''''''''
SUB tiraLabel (labelName$)

  tiraCheckActive ("tiraLabel")
  IF tiraLineCheck THEN EXIT SUB

  firstChar$ = LEFT$(labelName$, 1)

  IF firstChar$ <> "@" THEN
    throwCompilerError "Internal labels must use @ prefix", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_LABEL
  tiraCode$(t.LineCount) = labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraLabel

''''''''''''''''''''''''
FUNCTION tiraLabelCreateNew$ (baseName$)

  tiraCheckActive ("tiraLabelCreateNew$")

  ' Creates a unique jump label globally unique across the file (e.g., @loopLbl_5)
  tempName$ = "@" + baseName$ + "_" + LTRIM$(RTRIM$(STR$(t.TiraVarCounter)))
  t.TiraVarCounter = t.TiraVarCounter + 1

  tiraLabelCreateNew$ = tempName$

END FUNCTION ' tiraLabelCreateNew$

''''''''''''''''''''''''
SUB tiraLeaSIB (dest$, baseVar$, indexVar$, scaleStr$)

  tiraCheckActive ("tiraLeaSIB")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_LEA_SIB
  tiraCode$(t.LineCount) = dest$ + ", " + baseVar$ + ", " + indexVar$ + ", " + scaleStr$
  t.LineCount = t.LineCount + 1

END SUB ' tiraLeaSIB

''''''''''''''''''''''''
FUNCTION tiraLineCheck

  tiraLineCheck = 0

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    tira_Cancel ' <-- ADD THIS
    tiraLineCheck = 1
  END IF

END FUNCTION ' tiraLineCheck

''''''''''''''''''''''''
SUB tiraMemcpy (destAddr$, srcAddr$, lenVal$)

  tiraCheckActive ("tiraMemcpy")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_MEMCPY
  tiraCode$(t.LineCount) = destAddr$ + ", " + srcAddr$ + ", " + lenVal$
  t.LineCount = t.LineCount + 1

END SUB ' tiraMemcpy

''''''''''''''''''''''''
SUB tiraMemSet (destAddr$, valStr$, lenVal$)

  tiraCheckActive ("tiraMemSet")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_MEMSET
  tiraCode$(t.LineCount) = destAddr$ + ", " + valStr$ + ", " + lenVal$
  t.LineCount = t.LineCount + 1

END SUB ' tiraMemSet

''''''''''''''''''''''''
SUB tiraNew (opConst AS LONG, argsStr$)

  tiraCheckActive ("tiraNew")

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA QUEUE OVERFLOW", ASIS, 0
    EXIT SUB
  END IF

  IF opConst = TC_INVALID OR opConst >= TC_OUTOFRANGE THEN
    throwCompilerError "INVALID TC_", ASIS, 0
    EXIT SUB
  END IF

  ' If we are compiling runtimes, but the safe wrapper is OFF, block manual ABI commands
  IF isCompilingRT = 1 AND rtWrapperActive = 0 THEN
    IF opConst = TC_ABI_PROLOGUE OR opConst = TC_ABI_EPILOGUE OR opConst = TC_ABI_READ_ARG OR opConst = TC_ABI_WRITE_RET THEN
      throwCompilerError "MANUAL ABI COMMANDS NOT ALLOWED IN RUNTIMES, USE tiraRT_Prologue", ASIS, 0
      EXIT SUB
    END IF
  END IF

  tiraCmd(t.LineCount) = opConst
  tiraCode$(t.LineCount) = argsStr$

  t.LineCount = t.LineCount + 1

END SUB ' tiraNew

''''''''''''''''''''''''
FUNCTION tiraParseExpression$ (startIdx, endIdx, allowImplicit)

  tiraCheckActive ("tiraParseExpression$")

  DIM valStack$(64)
  DIM valType(64) AS LONG
  DIM valVIdx(64) AS LONG
  DIM opStack(64) AS LONG
  DIM opVIdx(64) AS LONG
  DIM opUdtOffset(64) AS LONG
  DIM opTargetType(64) AS LONG
  DIM opArgCount(64) AS LONG

  DIM valTop AS LONG
  DIM opTop AS LONG
  DIM prState AS LONG
  DIM tVal AS LONG
  DIM tVal2 AS LONG
  DIM leafEnd AS LONG
  DIM foundParen AS LONG
  DIM opVal AS LONG
  DIM prec AS LONG
  DIM topOp AS LONG
  DIM topPrec AS LONG
  DIM popIt AS LONG
  DIM opFinalVal AS LONG
  DIM nxtVal AS LONG
  DIM isFuncOrArray AS LONG
  DIM closeParen AS LONG
  DIM fieldName$
  DIM uIdx AS LONG
  DIM fieldFound AS LONG
  DIM iField AS LONG
  DIM funcOp AS LONG

  '''' Duck typing lookahead
  ff = checkExpressionForString(startIdx, endIdx)

  IF ff = 1 THEN
    expectedSymType = TYPE_STRING
  ELSE
    expectedSymType = TYPE_SINGLE
  END IF

  valTop = 0
  opTop = 0
  prState = 0 ' 0 = expect operand/unary/lparen, 1 = expect binary/rparen
  ix = startIdx

  DO WHILE ix <= endIdx
    IF t.IsActive = 0 THEN
      tiraParseExpression$ = ""
      EXIT FUNCTION
    END IF

    tVal = lineTokenVals(ix)

    IF prState = 0 THEN

      SELECT CASE tVal

        CASE TOK_OP_LPAREN
          opStack(opTop) = TOK_OP_LPAREN
          opTop = opTop + 1
          ix = ix + 1

        CASE TOK_OP_RPAREN ' Empty parentheses handling for root array requests e.g., A()
          foundParen = 0
          DO WHILE opTop > 0
            opVal = opStack(opTop - 1)
            IF opVal = TOK_OP_LPAREN THEN
              foundParen = 1
              EXIT DO
            END IF
            opTop = opTop - 1
            ff = tiraScheduleShuntingOp(opVal, valStack$(), valType(), valTop)
            IF ff = 0 THEN
              tiraParseExpression$ = ""
              EXIT FUNCTION
            END IF
            valTop = returnedData2
          LOOP

          IF foundParen = 0 THEN
            throwCompilerError "UNMATCHED PARENTHESIS", ASIS, 0
            tiraParseExpression$ = ""
            EXIT FUNCTION
          END IF

          opTop = opTop - 1 ' Pop LPAREN

          IF opTop > 0 THEN
            topOp = opStack(opTop - 1)
            IF topOp = SHUNT_FUNC OR topOp = SHUNT_ARRAY THEN
              opArgCount(opTop - 1) = 0
              opTop = opTop - 1
              ff = tiraScheduleFuncOrArray(topOp, valTop, valStack$(), valType(), valVIdx(), opArgCount(opTop), opVIdx(opTop), opTargetType(opTop), opUdtOffset(opTop))
              IF ff = 0 THEN
                tiraParseExpression$ = ""
                EXIT FUNCTION
              END IF
              valTop = returnedData2

              IF topOp = SHUNT_ARRAY THEN
                IF opUdtOffset(opTop) > 0 THEN ix = ix + 2 ' Skip the '.' and 'FieldName'
              END IF
            END IF
          END IF
          ix = ix + 1
          prState = 1

        CASE TOK_OP_MINUS
          opStack(opTop) = TOK_OP_UNARY_MINUS
          opTop = opTop + 1
          ix = ix + 1

        CASE TOK_NOT
          opStack(opTop) = TOK_OP_UNARY_NOT
          opTop = opTop + 1
          ix = ix + 1

        CASE ELSE
          isFuncOrArray = 0
          IF tVal = 0 OR tVal = TOK_CINT OR tVal = TOK_CLNG OR tVal = TOK_CSNG OR tVal = TOK_CDBL THEN
            IF ix + 1 <= endIdx THEN
              IF lineTokenVals(ix + 1) = 256 + ASC("(") THEN
                isFuncOrArray = 1
              END IF
            END IF
          END IF

          IF isFuncOrArray = 1 THEN
            IF tVal = TOK_CINT OR tVal = TOK_CLNG OR tVal = TOK_CSNG OR tVal = TOK_CDBL THEN
              opStack(opTop) = SHUNT_CAST

              SELECT CASE tVal

                CASE TOK_CINT: opVIdx(opTop) = TYPE_INTEGER
                CASE TOK_CLNG: opVIdx(opTop) = TYPE_LONG
                CASE TOK_CSNG: opVIdx(opTop) = TYPE_SINGLE
                CASE TOK_CDBL: opVIdx(opTop) = TYPE_DOUBLE

              END SELECT ' tVal

              opArgCount(opTop) = 1
              opTop = opTop + 1
              ix = ix + 1
            ELSE
              vName$ = UCASE$(lineTokens$(ix))
              IF findSymbol(vName$) THEN
                vIdx = returnedData2
                vDataType = symbols(vIdx).DataType
              ELSE
                IF allowImplicit = 0 THEN
                  throwCompilerError "UNDECLARED VARIABLE OR FUNCTION '" + vName$ + "'", ASIS, 0
                  tiraParseExpression$ = ""
                  EXIT FUNCTION
                ELSE
                  ff = resolveSymbol(vName$)
                  IF ff = 0 THEN
                    tiraParseExpression$ = ""
                    EXIT FUNCTION
                  END IF
                  vIdx = returnedData2
                  vDataType = returnedData3
                END IF
              END IF

              IF symbols(vIdx).SubIndex <> 0 THEN
                opStack(opTop) = SHUNT_FUNC
                opVIdx(opTop) = symbols(vIdx).SubIndex
                opArgCount(opTop) = 1
                opTop = opTop + 1
                ix = ix + 1
              ELSE
                opStack(opTop) = SHUNT_ARRAY
                opVIdx(opTop) = vIdx
                opArgCount(opTop) = 1
                opTargetType(opTop) = vDataType
                opUdtOffset(opTop) = 0

                ff = findMatchingParen(ix + 1, endIdx)
                IF ff = 1 THEN
                  closeParen = returnedData2
                  IF closeParen + 1 <= endIdx THEN
                    IF lineTokenVals(closeParen + 1) = 256 + ASC(".") THEN
                      IF closeParen + 2 <= endIdx THEN
                        fieldName$ = UCASE$(lineTokens$(closeParen + 2))
                        IF vDataType <> TYPE_UDT THEN
                          throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
                          tiraParseExpression$ = ""
                          EXIT FUNCTION
                        END IF
                        uIdx = symbols(vIdx).UDTIndex
                        fieldFound = 0
                        FOR iField = 0 TO udts(uIdx).FieldCount - 1
                          IF RTRIM$(udtFields(uIdx, iField).FieldName) = fieldName$ THEN
                            opUdtOffset(opTop) = udtFields(uIdx, iField).Offset
                            opTargetType(opTop) = udtFields(uIdx, iField).DataType
                            fieldFound = 1
                            EXIT FOR
                          END IF
                        NEXT
                        IF fieldFound = 0 THEN
                          throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
                          tiraParseExpression$ = ""
                          EXIT FUNCTION
                        END IF
                      END IF
                    END IF
                  END IF
                END IF

                opTop = opTop + 1
                ix = ix + 1
              END IF
            END IF
          ELSE
            ' Isolate flat leaf for tiraParseFactor$ (Literal, Scalar, UDT Field)
            leafEnd = ix
            IF tVal = 0 THEN
              IF ix + 1 <= endIdx THEN
                IF lineTokenVals(ix + 1) = 256 + ASC(".") THEN
                  IF ix + 2 <= endIdx THEN
                    leafEnd = ix + 2
                  END IF
                END IF
              END IF
            END IF

            leafVar$ = tiraParseFactor$(ix, leafEnd, allowImplicit)
            IF leafVar$ = "" THEN
              tiraParseExpression$ = ""
              EXIT FUNCTION
            END IF

            valStack$(valTop) = leafVar$
            valType(valTop) = exprIs.DataType
            valVIdx(valTop) = returnedData3
            valTop = valTop + 1

            ix = leafEnd + 1
            prState = 1
          END IF

      END SELECT ' tVal

    ELSE ' prState = 1
      IF tVal = 256 + ASC(",") THEN
        foundParen = 0
        DO WHILE opTop > 0
          topOp = opStack(opTop - 1)
          IF topOp = TOK_OP_LPAREN THEN
            foundParen = 1
            EXIT DO
          END IF
          opTop = opTop - 1
          ff = tiraScheduleShuntingOp(topOp, valStack$(), valType(), valTop)
          IF ff = 0 THEN
            tiraParseExpression$ = ""
            EXIT FUNCTION
          END IF
          valTop = returnedData2
        LOOP

        IF foundParen = 0 THEN
          throwCompilerError "MISPLACED COMMA", ASIS, 0
          tiraParseExpression$ = ""
          EXIT FUNCTION
        END IF

        IF opTop > 1 THEN
          funcOp = opStack(opTop - 2)
          IF funcOp = SHUNT_FUNC OR funcOp = SHUNT_ARRAY THEN
            opArgCount(opTop - 2) = opArgCount(opTop - 2) + 1
          END IF
        END IF

        ix = ix + 1
        prState = 0

      ELSE
        IF tVal = TOK_OP_RPAREN THEN
          foundParen = 0
          DO WHILE opTop > 0
            topOp = opStack(opTop - 1)
            IF topOp = TOK_OP_LPAREN THEN
              foundParen = 1
              EXIT DO
            END IF
            opTop = opTop - 1
            ff = tiraScheduleShuntingOp(topOp, valStack$(), valType(), valTop)
            IF ff = 0 THEN
              tiraParseExpression$ = ""
              EXIT FUNCTION
            END IF
            valTop = returnedData2
          LOOP

          IF foundParen = 0 THEN
            throwCompilerError "UNMATCHED PARENTHESIS", ASIS, 0
            tiraParseExpression$ = ""
            EXIT FUNCTION
          END IF
          opTop = opTop - 1 ' Pop LPAREN

          IF opTop > 0 THEN
            topOp = opStack(opTop - 1)
            IF topOp = SHUNT_FUNC OR topOp = SHUNT_ARRAY OR topOp = SHUNT_CAST THEN
              opTop = opTop - 1
              ff = tiraScheduleFuncOrArray(topOp, valTop, valStack$(), valType(), valVIdx(), opArgCount(opTop), opVIdx(opTop), opTargetType(opTop), opUdtOffset(opTop))
              IF ff = 0 THEN
                tiraParseExpression$ = ""
                EXIT FUNCTION
              END IF
              valTop = returnedData2

              IF topOp = SHUNT_ARRAY THEN
                IF opUdtOffset(opTop) > 0 THEN ix = ix + 2 ' Skip the '.' and 'FieldName'
              END IF
            END IF
          END IF

          ix = ix + 1

        ELSE
          IF tVal = TOK_OP_PLUS OR tVal = TOK_OP_MINUS OR tVal = TOK_OP_MUL OR tVal = TOK_OP_DIV OR tVal = TOK_OP_IDIV OR tVal = TOK_OP_POW OR tVal = TOK_OP_EQUAL OR tVal = TOK_OP_LESS OR tVal = TOK_OP_GREATER OR tVal = TOK_AND OR tVal = TOK_OR THEN

            opFinalVal = tVal

            SELECT CASE tVal

              CASE TOK_OP_LESS
                IF ix + 1 <= endIdx THEN
                  nxtVal = lineTokenVals(ix + 1)

                  SELECT CASE nxtVal

                    CASE TOK_OP_EQUAL
                      opFinalVal = TOK_OP_LESS_EQUAL
                      ix = ix + 1

                    CASE TOK_OP_GREATER
                      opFinalVal = TOK_OP_NOT_EQUAL
                      ix = ix + 1

                  END SELECT ' nxtVal

                END IF

              CASE TOK_OP_GREATER
                IF ix + 1 <= endIdx THEN
                  nxtVal = lineTokenVals(ix + 1)
                  IF nxtVal = TOK_OP_EQUAL THEN
                    opFinalVal = TOK_OP_GREATER_EQUAL
                    ix = ix + 1
                  END IF
                END IF

            END SELECT ' tVal

            prec = tiraGetPrecedence(opFinalVal)

            DO WHILE opTop > 0
              topOp = opStack(opTop - 1)
              IF topOp = TOK_OP_LPAREN THEN EXIT DO

              topPrec = tiraGetPrecedence(topOp)

              popIt = 0
              IF opFinalVal = TOK_OP_POW THEN
                IF topPrec > prec THEN popIt = 1
              ELSE
                IF topPrec >= prec THEN popIt = 1
              END IF

              IF popIt = 1 THEN
                opTop = opTop - 1
                ff = tiraScheduleShuntingOp(topOp, valStack$(), valType(), valTop)
                IF ff = 0 THEN
                  tiraParseExpression$ = ""
                  EXIT FUNCTION
                END IF
                valTop = returnedData2
              ELSE
                EXIT DO
              END IF
            LOOP

            opStack(opTop) = opFinalVal
            opTop = opTop + 1
            ix = ix + 1
            prState = 0
          ELSE
            throwCompilerError "EXPECTED OPERATOR", ASIS, 0
            tiraParseExpression$ = ""
            EXIT FUNCTION
          END IF
        END IF
      END IF
    END IF
  LOOP

  ' Process remaining operators
  DO WHILE opTop > 0
    opTop = opTop - 1
    opVal = opStack(opTop)
    IF opVal = TOK_OP_LPAREN THEN
      throwCompilerError "UNMATCHED PARENTHESIS", ASIS, 0
      tiraParseExpression$ = ""
      EXIT FUNCTION
    END IF

    ff = tiraScheduleShuntingOp(opVal, valStack$(), valType(), valTop)
    IF ff = 0 THEN
      tiraParseExpression$ = ""
      EXIT FUNCTION
    END IF
    valTop = returnedData2
  LOOP

  IF valTop <> 1 THEN
    throwCompilerError "MALFORMED EXPRESSION", ASIS, 0
    tiraParseExpression$ = ""
    EXIT FUNCTION
  END IF

  exprIs.DataType = valType(0)
  exprIs.IsTemp = 1
  tiraParseExpression$ = valStack$(0)

END FUNCTION ' tiraParseExpression$

''''''''''''''''''''''''
FUNCTION tiraParseExpressionInt$ (startIdx, endIdx, allowImplicit, errMsg$)

  tiraCheckActive (" tiraParseExpressionInt$")

  DIM resVar$
  resVar$ = tiraParseExpressionNumeric$(startIdx, endIdx, allowImplicit, errMsg$)

  IF resVar$ = "" THEN
    tiraParseExpressionInt$ = ""
    EXIT FUNCTION
  END IF

  tiraParseExpressionInt$ = tiraForceInt$(resVar$)

END FUNCTION '  tiraParseExpressionInt$

''''''''''''''''''''''''
FUNCTION tiraParseExpressionNumeric$ (startIdx, endIdx, allowImplicit, errMsg$)

  tiraCheckActive ("tiraParseNumericExpr$")

  DIM resVar$
  resVar$ = tiraParseExpression$(startIdx, endIdx, allowImplicit)

  IF resVar$ = "" THEN
    tira_Cancel
    tiraParseExpressionNumeric$ = ""
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerErrorAndCancelTira errMsg$, ASIS, 0
    tiraParseExpressionNumeric$ = ""
    EXIT FUNCTION
  END IF

  tiraParseExpressionNumeric$ = resVar$

END FUNCTION ' tiraParseExpressionNumeric$

''''''''''''''''''''''''
FUNCTION tiraParseFactor$ (startIdx, endIdx, allowImplicit)

  tiraCheckActive ("tiraParseFactor$")

  DIM tVal AS LONG
  DIM vIdx AS LONG
  DIM vDataType AS LONG
  DIM firstChar AS STRING * 1
  DIM hasField AS LONG
  DIM udtOffset AS LONG
  DIM uIdx AS LONG
  DIM fieldFound AS LONG
  DIM iField AS LONG
  DIM tokIdx AS LONG
  DIM resVar$

  '''' Literals
  IF startIdx = endIdx THEN
    tVal = lineTokenVals(startIdx)
    IF tVal = 0 THEN
      firstChar = LEFT$(lineTokens$(startIdx), 1)
      IF firstChar = CHR$(34) THEN
        lit$ = extractQuotes$(lineTokens$(startIdx))
        ff = resolveSymbol("!G_EVAL_LIT__" + cTrNum$(t.TiraVarCounter) + "_DESC$")
        t.TiraVarCounter = t.TiraVarCounter + 1
        IF ff = 1 THEN
          vIdx = returnedData2
          strVarData$(vIdx) = lit$
          exprIs.DataType = TYPE_STRING
          exprIs.IsTemp = 0
          return3 vIdx
          tiraParseFactor$ = RTRIM$(symbols(vIdx).RecordName)
          EXIT FUNCTION
        END IF
        tiraParseFactor$ = ""
        EXIT FUNCTION
      ELSE
        IF (firstChar >= "0" AND firstChar <= "9") OR firstChar = "-" OR firstChar = "." THEN
          IF INSTR(lineTokens$(startIdx), ".") > 0 THEN
            exprIs.DataType = TYPE_DOUBLE
          ELSE
            exprIs.DataType = TYPE_LONG
          END IF
          exprIs.IsTemp = 0
          return3 -1
          tiraParseFactor$ = lineTokens$(startIdx)
          EXIT FUNCTION
        END IF
      END IF
    END IF
  END IF

  '''' Identifiers (Scalars and UDT fields only. Parens, arrays, funcs natively stripped out via tiraParseExpression$)
  vTok$ = lineTokens$(startIdx)
  IF lineTokenVals(startIdx) = 0 AND LEN(vTok$) > 0 THEN
    firstChar = LEFT$(vTok$, 1)
    IF (firstChar >= "A" AND firstChar <= "Z") OR (firstChar >= "a" AND firstChar <= "z") OR firstChar = "!" OR firstChar = "~" THEN

      vName$ = UCASE$(vTok$)
      tokIdx = startIdx + 1

      hasField = 0
      IF tokIdx <= endIdx THEN
        IF lineTokenVals(tokIdx) = 256 + ASC(".") THEN hasField = 1
      END IF

      IF findSymbol(vName$) THEN
        vIdx = returnedData2
        vDataType = symbols(vIdx).DataType
      ELSE
        IF allowImplicit = 0 THEN
          throwCompilerError "UNDECLARED VARIABLE '" + vName$ + "'", ASIS, 0
          tiraParseFactor$ = ""
          EXIT FUNCTION
        ELSE
          ff = resolveSymbol(vName$)
          IF ff = 0 THEN
            tiraParseFactor$ = ""
            EXIT FUNCTION
          END IF
          vIdx = returnedData2
          vDataType = returnedData3
        END IF
      END IF

      udtOffset = 0
      targetType = vDataType

      IF hasField = 1 THEN
        tokIdx = tokIdx + 1
        IF tokIdx > endIdx THEN
          throwCompilerError "EXPECTED FIELD NAME", ASIS, 0
          tiraParseFactor$ = ""
          EXIT FUNCTION
        END IF
        fieldName$ = UCASE$(lineTokens$(tokIdx))
        tokIdx = tokIdx + 1

        IF vDataType <> TYPE_UDT THEN
          throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
          tiraParseFactor$ = ""
          EXIT FUNCTION
        END IF

        uIdx = symbols(vIdx).UDTIndex
        fieldFound = 0
        FOR iField = 0 TO udts(uIdx).FieldCount - 1
          IF RTRIM$(udtFields(uIdx, iField).FieldName) = fieldName$ THEN
            udtOffset = udtFields(uIdx, iField).Offset
            targetType = udtFields(uIdx, iField).DataType
            fieldFound = 1
            EXIT FOR
          END IF
        NEXT
        IF fieldFound = 0 THEN
          throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
          tiraParseFactor$ = ""
          EXIT FUNCTION
        END IF
      END IF

      ff = verifyNoExtraTokens(endIdx, tokIdx - 1, "FACTOR")
      IF ff = 0 THEN
        tiraParseFactor$ = ""
        EXIT FUNCTION
      END IF

      resVar$ = tiraDimVar$("T", targetType)

      IF udtOffset = 0 THEN
        tiraAssign resVar$, RTRIM$(symbols(vIdx).RecordName)
        IF targetType = TYPE_STRING THEN
          skipNullLbl$ = tiraLabelCreateNew$("SKIP_NULL")
          tiraJmpCond "JNE", resVar$, "0", skipNullLbl$
          tiraAssign resVar$, "!G_SYS_EMPTY_DESC$"
          tiraLabel skipNullLbl$
        END IF
      ELSE
        finalAddr$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), "", "", udtOffset)
        IF finalAddr$ = "" THEN
          tiraParseFactor$ = ""
          EXIT FUNCTION
        END IF

        tiraNew TC_READ_MEM, resVar$ + ", " + finalAddr$

        IF targetType = TYPE_STRING THEN
          skipNullLbl$ = tiraLabelCreateNew$("SKIP_NULL")
          tiraJmpCond "JNE", resVar$, "0", skipNullLbl$
          tiraAssign resVar$, "!G_SYS_EMPTY_DESC$"
          tiraLabel skipNullLbl$
        END IF
      END IF

      exprIs.DataType = targetType
      exprIs.IsTemp = 0
      return3 vIdx
      tiraParseFactor$ = resVar$
      EXIT FUNCTION
    END IF
  END IF

  throwCompilerError "MALFORMED EXPRESSION LEAF (Missing hoist?)", ASIS, 0
  tiraParseFactor$ = ""

END FUNCTION ' tiraParseFactor$

''''''''''''''''''''''''
FUNCTION tiraParseRhsUdtBase$ (startTokIdx, exprEndBoundary, passLhsUdtIndex)

  DIM rhsTokIdx AS LONG
  DIM rhsName$
  DIM rhsIdx AS LONG
  DIM rhsHasIndex AS LONG
  DIM rhsParenStart AS LONG
  DIM rhsCloseParenIdx AS LONG
  DIM rhsHasComma AS LONG
  DIM rhsCommaIdx AS LONG
  DIM rhsUdtOffset AS LONG
  DIM rhsUdtIndex AS LONG
  DIM isRhsUdtFound AS LONG
  DIM rhsFieldName$
  DIM rUIdx AS LONG
  DIM rFieldFound AS LONG
  DIM iField AS LONG
  DIM rhsX$
  DIM rhsY$
  DIM tempBase$

  tiraCheckActive ("tiraParseRhsUdtBase$")

  rhsTokIdx = startTokIdx
  IF rhsTokIdx > exprEndBoundary THEN
    throwCompilerErrorAndCancelTira "EXPECTED UDT VARIABLE", ASIS, 0
    tiraParseRhsUdtBase$ = ""
    EXIT FUNCTION
  END IF

  rhsName$ = UCASE$(lineTokens$(rhsTokIdx))
  ff = resolveSymbol(rhsName$)
  IF ff = 0 THEN
    tira_Cancel
    tiraParseRhsUdtBase$ = ""
    EXIT FUNCTION
  END IF
  rhsIdx = returnedData2

  rhsTokIdx = rhsTokIdx + 1
  rhsHasIndex = 0
  rhsParenStart = 0
  rhsCloseParenIdx = 0
  rhsHasComma = 0
  rhsCommaIdx = 0

  IF rhsTokIdx <= exprEndBoundary THEN
    IF lineTokenVals(rhsTokIdx) = 256 + ASC("(") THEN
      rhsHasIndex = 1
      rhsParenStart = rhsTokIdx

      IF findMatchingParen(rhsTokIdx, exprEndBoundary) = 1 THEN
        rhsCloseParenIdx = returnedData2
      ELSE
        throwCompilerErrorAndCancelTira "MISSING )", ASIS, 0
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF

      rhsCommaIdx = findComma(rhsTokIdx + 1, rhsCloseParenIdx - 1)
      IF rhsCommaIdx > 0 THEN
        rhsHasComma = 1
      ELSE
        rhsHasComma = 0
      END IF

      rhsTokIdx = rhsCloseParenIdx + 1
    END IF
  END IF

  rhsUdtOffset = 0
  rhsUdtIndex = 0
  isRhsUdtFound = 0

  IF symbols(rhsIdx).DataType = TYPE_UDT THEN
    rhsUdtIndex = symbols(rhsIdx).UDTIndex
    isRhsUdtFound = 1
  END IF

  IF rhsTokIdx <= exprEndBoundary THEN
    IF lineTokenVals(rhsTokIdx) = 256 + ASC(".") THEN
      rhsTokIdx = rhsTokIdx + 1
      IF rhsTokIdx > exprEndBoundary THEN
        throwCompilerErrorAndCancelTira "EXPECTED FIELD NAME", ASIS, 0
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF

      rhsFieldName$ = UCASE$(lineTokens$(rhsTokIdx))
      rhsTokIdx = rhsTokIdx + 1

      IF symbols(rhsIdx).DataType <> TYPE_UDT THEN
        throwCompilerErrorAndCancelTira "VARIABLE IS NOT A UDT", ASIS, 0
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF

      rUIdx = symbols(rhsIdx).UDTIndex
      rFieldFound = 0
      FOR iField = 0 TO udts(rUIdx).FieldCount - 1
        IF RTRIM$(udtFields(rUIdx, iField).FieldName) = rhsFieldName$ THEN
          rhsUdtOffset = udtFields(rUIdx, iField).Offset
          IF udtFields(rUIdx, iField).DataType <> TYPE_UDT THEN
            throwCompilerErrorAndCancelTira "TYPE MISMATCH", ASIS, 0
            tiraParseRhsUdtBase$ = ""
            EXIT FUNCTION
          END IF
          rhsUdtIndex = udtFields(rUIdx, iField).UDTIndex
          isRhsUdtFound = 1
          rFieldFound = 1
          EXIT FOR
        END IF
      NEXT

      IF rFieldFound = 0 THEN
        throwCompilerErrorAndCancelTira "UDT FIELD NOT FOUND", ASIS, 0
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF
    END IF
  END IF

  IF isRhsUdtFound = 0 THEN
    throwCompilerErrorAndCancelTira "RHS IS NOT A UDT", ASIS, 0
    tiraParseRhsUdtBase$ = ""
    EXIT FUNCTION
  END IF

  IF rhsUdtIndex <> passLhsUdtIndex THEN
    throwCompilerErrorAndCancelTira "UDT TYPE MISMATCH", ASIS, 0
    tiraParseRhsUdtBase$ = ""
    EXIT FUNCTION
  END IF

  rhsX$ = ""
  rhsY$ = ""
  IF rhsHasIndex = 1 THEN
    IF symbols(rhsIdx).IsArray = 0 THEN
      throwCompilerErrorAndCancelTira "ARRAY NOT DIMMED", ASIS, 0
      tiraParseRhsUdtBase$ = ""
      EXIT FUNCTION
    END IF

    IF rhsHasComma = 0 THEN
      rhsX$ = tiraParseExpressionInt$(rhsParenStart + 1, rhsCloseParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
      IF rhsX$ = "" THEN
        tira_Cancel
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF
    ELSE
      rhsX$ = tiraParseExpressionInt$(rhsParenStart + 1, rhsCommaIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
      IF rhsX$ = "" THEN
        tira_Cancel
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF

      rhsY$ = tiraParseExpressionInt$(rhsCommaIdx + 1, rhsCloseParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
      IF rhsY$ = "" THEN
        tira_Cancel
        tiraParseRhsUdtBase$ = ""
        EXIT FUNCTION
      END IF
    END IF
  END IF

  tempBase$ = tiraFrontendCalcAddress$(RTRIM$(symbols(rhsIdx).RecordName), rhsX$, rhsY$, rhsUdtOffset)
  IF tempBase$ = "" THEN
    tira_Cancel
    tiraParseRhsUdtBase$ = ""
    EXIT FUNCTION
  END IF

  tiraParseRhsUdtBase$ = tempBase$

END FUNCTION ' tiraParseRhsUdtBase$

''''''''''''''''''''''''
SUB tiraOp (opConst AS LONG, destOrIAT$, src1$, src2$)

  tiraCheckActive ("tiraOp")
  IF tiraLineCheck THEN EXIT SUB

  SELECT CASE opConst

    CASE TC_ADD, TC_SUB, TC_MUL, TC_DIV, TC_IDIV, TC_MOD, TC_AND, TC_OR, TC_POW, TC_CONCAT, TC_SHL, TC_SHR, TC_NEG, TC_NOT, TC_CALL, TC_ADDRESS_OF, TC_CAST, TC_COMPARE, TC_TEST, TC_JCC, TC_LEA_SIB
      ' Valid
    CASE ELSE
      throwCompilerError "UNKNOWN OR UNSUPPORTED TIRA CONSTANT IN OP", ASIS, 0
      EXIT SUB

  END SELECT ' opConst

  tiraCmd(t.LineCount) = opConst

  SELECT CASE opConst

    CASE TC_NEG, TC_NOT, TC_COMPARE, TC_TEST, TC_JCC
      tiraCode$(t.LineCount) = destOrIAT$ + ", " + src1$

    CASE TC_CALL
      IF src1$ = "0" OR src1$ = "" THEN
        tiraCode$(t.LineCount) = destOrIAT$ + ", 0"
      ELSE
        tiraCode$(t.LineCount) = destOrIAT$ + ", " + src1$ + ", " + src2$
      END IF

    CASE ELSE
      tiraCode$(t.LineCount) = destOrIAT$ + ", " + src1$ + ", " + src2$

  END SELECT ' opConst

  t.LineCount = t.LineCount + 1

END SUB ' tiraOp

''''''''''''''''''''''''
FUNCTION tiraResolveHoistVar$ (prefix$, suffix$)

  tiraCheckActive ("tiraResolveHoistVar$")

  tempName$ = "!G_EVAL_HOIST_" + prefix$ + "_" + cTrNum$(t.TiraVarCounter) + suffix$
  t.TiraVarCounter = t.TiraVarCounter + 1

  ff = resolveSymbol(tempName$)
  IF ff = 0 THEN
    tira_Cancel
    tiraResolveHoistVar$ = ""
    EXIT FUNCTION
  END IF

  tiraResolveHoistVar$ = tempName$

END FUNCTION ' tiraResolveHoistVar$

''''''''''''''''''''''''
SUB tiraRT_Epilogue

  tiraCheckActive ("tiraRT_Epilogue")

  tiraCode$(rtPrologueIdx) = LTRIM$(STR$(rtFrameSize))
  tiraNew TC_ABI_EPILOGUE, LTRIM$(STR$(rtFrameSize))

  ' Turn the safe wrapper off for the next helper in the queue
  rtWrapperActive = 0

END SUB ' tiraRT_Epilogue

''''''''''''''''''''''''
SUB tiraRT_Prologue

  tiraCheckActive ("tiraRT_Prologue")

  isCompilingRT = 1

  ' Turn the safe wrapper on so tiraNew allows the ABI stack allocation commands
  rtWrapperActive = 1

  rtFrameSize = 0
  rtPrologueIdx = t.LineCount

  tiraNew TC_ABI_PROLOGUE, "0"

END SUB ' tiraRT_Prologue

''''''''''''''''''''''''
SUB tiraScheduleArrayFree (vIdx AS LONG)

  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM totalElems AS LONG
  DIM uIdx AS LONG
  DIM dynamicOffsets(64) AS LONG
  DIM numDynamicOffsets AS LONG
  DIM iOff AS LONG
  DIM curOff AS LONG
  DIM fixedLen AS LONG

  tiraCheckActive ("tiraScheduleArrayFree")

  arrPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraAssign arrPtr$, RTRIM$(symbols(vIdx).RecordName)

  skipFreeLbl$ = tiraLabelCreateNew$("SKIP_ARR_FREE")
  tiraJmpCond "JE", arrPtr$, "0", skipFreeLbl$

  dt = symbols(vIdx).DataType
  numDynamicOffsets = 0
  elemSize = 8

  SELECT CASE dt

    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
    CASE TYPE_UDT
      elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
      uIdx = symbols(vIdx).UDTIndex
      FOR ii = 0 TO udts(uIdx).FieldCount - 1
        IF udtFields(uIdx, ii).DataType = TYPE_STRING AND udtFields(uIdx, ii).IsDynamicString = 1 THEN
          dynamicOffsets(numDynamicOffsets) = udtFields(uIdx, ii).Offset
          numDynamicOffsets = numDynamicOffsets + 1
        END IF
      NEXT

    CASE TYPE_STRING
      fixedLen = retFixedStringLength(vIdx)
      IF fixedLen > 0 THEN
        elemSize = fixedLen
      ELSE
        elemSize = 8
        dynamicOffsets(0) = 0
        numDynamicOffsets = 1
      END IF

  END SELECT ' dt

  totalElems = symbols(vIdx).Size
  IF symbols(vIdx).Size2 > 0 THEN totalElems = totalElems * symbols(vIdx).Size2

  IF numDynamicOffsets > 0 THEN
    itr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraAssign itr$, arrPtr$

    endPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, endPtr$, arrPtr$, LTRIM$(STR$(totalElems * elemSize))

    loopTop$ = tiraLabelCreateNew$("FREE_ARR_LOOP")
    loopDone$ = tiraLabelCreateNew$("FREE_ARR_DONE")

    tiraLabel loopTop$
    tiraJmpCond "JGE", itr$, endPtr$, loopDone$

    FOR iOff = 0 TO numDynamicOffsets - 1
      curOff = dynamicOffsets(iOff)

      descAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
      IF curOff > 0 THEN
        tiraOp TC_ADD, descAddr$, itr$, LTRIM$(STR$(curOff))
      ELSE
        tiraAssign descAddr$, itr$
      END IF

      descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraNew TC_READ_MEM, descPtr$ + ", " + descAddr$

      skipFreeDescLbl$ = tiraLabelCreateNew$("SKIP_FREE_DESC")
      tiraJmpCond "JE", descPtr$, "0", skipFreeDescLbl$

      flagVal$ = tiraDimVar$("T", TYPE_LONG)
      flagPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_ADD, flagPtr$, descPtr$, "16"
      tiraNew TC_READ_MEM, flagVal$ + ", " + flagPtr$

      tiraJmpCond "JNE", flagVal$, "1", skipFreeDescLbl$

      dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraNew TC_READ_MEM, dataPtr$ + ", " + descPtr$

      tiraJmpCond "JE", dataPtr$, "0", skipFreeDescLbl$

      tiraCall "IAT_HEAPFREE", 3, "!G_MEM_PROCESS_HEAP_PTR, 0, " + dataPtr$

      tiraLabel skipFreeDescLbl$
    NEXT

    tiraOp TC_ADD, itr$, itr$, LTRIM$(STR$(elemSize))
    tiraJmp loopTop$

    tiraLabel loopDone$
  END IF

  tiraCall "IAT_HEAPFREE", 3, "!G_MEM_PROCESS_HEAP_PTR, 0, " + arrPtr$
  tiraLabel skipFreeLbl$

END SUB ' tiraScheduleArrayFree

''''''''''''''''''''''''
FUNCTION tiraScheduleFuncOrArray (opVal AS LONG, passValTop AS LONG, valStack$(), valType() AS LONG, valVIdx() AS LONG, passArgCount AS LONG, passOpVIdx AS LONG, passOpTargetType AS LONG, passOpUdtOffset AS LONG)

  tiraCheckActive ("tiraScheduleFuncOrArray")

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM argCount AS LONG
  DIM argIdx AS LONG
  DIM resVar$
  DIM targetType AS LONG
  DIM udtOffset AS LONG
  DIM xVar$, yVar$
  DIM baseArgIdx AS LONG

  argCount = passArgCount

  SELECT CASE opVal

    CASE SHUNT_CAST
      castTargetType = passOpVIdx
      argVar$ = valStack$(passValTop - 1)
      resVar$ = tiraDimVar$("T", castTargetType)
      tiraOp TC_CAST, resVar$, argVar$, LTRIM$(STR$(castTargetType))
      valStack$(passValTop - 1) = resVar$
      valType(passValTop - 1) = castTargetType
      valVIdx(passValTop - 1) = -1
      tiraScheduleFuncOrArray = 1
      return2 passValTop
      EXIT FUNCTION

    CASE SHUNT_FUNC
      subIdx = passOpVIdx
      subName$ = RTRIM$(subs(subIdx).RecordName)

      IF argCount <> subs(subIdx).ArgCount THEN
        throwCompilerError "INCORRECT ARG COUNT FOR " + subName$, ASIS, 0
        tiraScheduleFuncOrArray = 0
        EXIT FUNCTION
      END IF

      baseArgIdx = passValTop - argCount

      FOR argIdx = 0 TO argCount - 1
        argVar$ = valStack$(baseArgIdx + argIdx)
        argDt = valType(baseArgIdx + argIdx)

        targetVarIdx = subArgVarIdx(subIdx, argIdx)
        targetType = symbols(targetVarIdx).DataType

        IF symbols(targetVarIdx).IsArray = 2 THEN
          IF argDt = TYPE_STRING AND targetType <> TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH ARG", ASIS, 0
            tiraScheduleFuncOrArray = 0
            EXIT FUNCTION
          END IF
          IF argDt <> TYPE_STRING AND targetType = TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH ARG", ASIS, 0
            tiraScheduleFuncOrArray = 0
            EXIT FUNCTION
          END IF

          targetVarName$ = "#" + LTRIM$(STR$(targetVarIdx))
          tiraAssign targetVarName$, argVar$

          srcArgIdx = valVIdx(baseArgIdx + argIdx)
          IF srcArgIdx <> -1 THEN
            srcBase$ = RTRIM$(symbols(srcArgIdx).RecordName)
            tgtBase$ = RTRIM$(symbols(targetVarIdx).RecordName)

            ff = resolveSymbol("!SYS_" + srcBase$ + "_AX_VAL")
            IF ff = 1 THEN srcAxIdx = returnedData2
            ff = resolveSymbol("!SYS_" + srcBase$ + "_AY_VAL")
            IF ff = 1 THEN srcAyIdx = returnedData2
            ff = resolveSymbol("!SYS_" + tgtBase$ + "_AX_VAL")
            IF ff = 1 THEN tgtAxIdx = returnedData2
            ff = resolveSymbol("!SYS_" + tgtBase$ + "_AY_VAL")
            IF ff = 1 THEN tgtAyIdx = returnedData2

            tiraAssign "#" + LTRIM$(STR$(tgtAxIdx)), "#" + LTRIM$(STR$(srcAxIdx))
            tiraAssign "#" + LTRIM$(STR$(tgtAyIdx)), "#" + LTRIM$(STR$(srcAyIdx))
          END IF
        ELSE
          targetVarName$ = "#" + LTRIM$(STR$(targetVarIdx))
          IF targetType = TYPE_STRING THEN
            tiraCall "RT_STR_ASSIGN", 2, targetVarName$ + ", " + argVar$
          ELSE
            tiraAssign targetVarName$, argVar$
          END IF
        END IF
      NEXT

      tiraCall subName$, 0, ""

      IF subs(subIdx).IsFunction = 1 THEN
        retVarIdx = subs(subIdx).ReturnVarIdx
        resType = symbols(retVarIdx).DataType
        resVar$ = tiraDimVar$("T", resType)
        tiraAssign resVar$, subName$
      ELSE
        resType = TYPE_LONG
        resVar$ = tiraDimVar$("T", TYPE_LONG)
        tiraAssign resVar$, "0"
      END IF

      passValTop = baseArgIdx
      valStack$(passValTop) = resVar$
      valType(passValTop) = resType
      valVIdx(passValTop) = -1
      passValTop = passValTop + 1

      tiraScheduleFuncOrArray = 1
      return2 passValTop
      EXIT FUNCTION

    CASE SHUNT_ARRAY
      vIdx = passOpVIdx
      targetType = passOpTargetType
      udtOffset = passOpUdtOffset

      IF argCount = 0 THEN
        resVar$ = tiraDimVar$("T", targetType)
        tiraAssign resVar$, RTRIM$(symbols(vIdx).RecordName)
      ELSE

        SELECT CASE argCount

          CASE 1
            xVar$ = valStack$(passValTop - 1)
            xVar$ = tiraForceInt$(xVar$)
            yVar$ = ""
            passValTop = passValTop - 1

          CASE 2
            yVar$ = valStack$(passValTop - 1)
            yVar$ = tiraForceInt$(yVar$)
            xVar$ = valStack$(passValTop - 2)
            xVar$ = tiraForceInt$(xVar$)
            passValTop = passValTop - 2

          CASE ELSE
            throwCompilerError "TOO MANY ARRAY INDICES", ASIS, 0
            tiraScheduleFuncOrArray = 0
            EXIT FUNCTION

        END SELECT ' argCount

        finalAddr$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), xVar$, yVar$, udtOffset)
        resVar$ = tiraDimVar$("T", targetType)
        tiraNew TC_READ_MEM, resVar$ + ", " + finalAddr$

        IF targetType = TYPE_STRING THEN
          skipNullLbl$ = tiraLabelCreateNew$("SKIP_NULL")
          tiraJmpCond "JNE", resVar$, "0", skipNullLbl$
          tiraAssign resVar$, "!G_SYS_EMPTY_DESC$"
          tiraLabel skipNullLbl$
        END IF
      END IF

      valStack$(passValTop) = resVar$
      valType(passValTop) = targetType
      valVIdx(passValTop) = vIdx
      passValTop = passValTop + 1

      tiraScheduleFuncOrArray = 1
      return2 passValTop
      EXIT FUNCTION

  END SELECT ' opVal

  tiraScheduleFuncOrArray = 0

END FUNCTION ' tiraScheduleFuncOrArray

''''''''''''''''''''''''
SUB tiraScheduleGC

  DIM dt AS LONG
  DIM uIdx AS LONG
  DIM fOffset AS LONG
  DIM iField AS LONG
  DIM vIdx AS LONG

  tiraCheckActive ("tiraScheduleGC")

  IF insideSub > 0 AND currentScopeID > 0 THEN
    FOR vIdx = 0 TO symbolCount - 1
      IF symbols(vIdx).ScopeID = currentScopeID AND symbols(vIdx).IsLocal = 1 THEN
        IF symbols(vIdx).IsArray = 2 THEN
          tiraScheduleArrayFree vIdx
        ELSE
          dt = symbols(vIdx).DataType

          IF dt = TYPE_STRING AND LEFT$(symbols(vIdx).RecordName, 1) <> "~" THEN
            descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
            tiraAssign descPtr$, RTRIM$(symbols(vIdx).RecordName)

            flagVal$ = tiraDimVar$("T", TYPE_LONG)
            flagPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
            tiraOp TC_ADD, flagPtr$, descPtr$, "16"
            tiraNew TC_READ_MEM, flagVal$ + ", " + flagPtr$

            skipFreeDescLbl$ = tiraLabelCreateNew$("SKIP_FREE_DESC")
            tiraJmpCond "JNE", flagVal$, "1", skipFreeDescLbl$

            dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
            tiraNew TC_READ_MEM, dataPtr$ + ", " + descPtr$

            tiraJmpCond "JE", dataPtr$, "0", skipFreeDescLbl$

            tiraCall "IAT_HEAPFREE", 3, "!G_MEM_PROCESS_HEAP_PTR, 0, " + dataPtr$

            tiraLabel skipFreeDescLbl$

          ELSE
            IF dt = TYPE_UDT THEN
              uIdx = symbols(vIdx).UDTIndex
              FOR iField = 0 TO udts(uIdx).FieldCount - 1
                IF udtFields(uIdx, iField).DataType = TYPE_STRING AND udtFields(uIdx, iField).IsDynamicString = 1 THEN
                  fOffset = udtFields(uIdx, iField).Offset

                  basePtr$ = tiraDimVar$("T", TYPE_INTEGER64)
                  tiraOp TC_ADDRESS_OF, basePtr$, RTRIM$(symbols(vIdx).RecordName), ""

                  descAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
                  IF fOffset > 0 THEN
                    tiraOp TC_ADD, descAddr$, basePtr$, LTRIM$(STR$(fOffset))
                  ELSE
                    tiraAssign descAddr$, basePtr$
                  END IF

                  descPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
                  tiraNew TC_READ_MEM, descPtr$ + ", " + descAddr$

                  skipFreeDescLbl$ = tiraLabelCreateNew$("SKIP_FREE_DESC")
                  tiraJmpCond "JE", descPtr$, "0", skipFreeDescLbl$

                  flagVal$ = tiraDimVar$("T", TYPE_LONG)
                  flagPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
                  tiraOp TC_ADD, flagPtr$, descPtr$, "16"
                  tiraNew TC_READ_MEM, flagVal$ + ", " + flagPtr$

                  tiraJmpCond "JNE", flagVal$, "1", skipFreeDescLbl$

                  dataPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
                  tiraNew TC_READ_MEM, dataPtr$ + ", " + descPtr$

                  tiraJmpCond "JE", dataPtr$, "0", skipFreeDescLbl$

                  tiraCall "IAT_HEAPFREE", 3, "!G_MEM_PROCESS_HEAP_PTR, 0, " + dataPtr$

                  tiraLabel skipFreeDescLbl$
                END IF
              NEXT
            END IF
          END IF
        END IF
      END IF
    NEXT
  END IF

END SUB ' tiraScheduleGC

''''''''''''''''''''''''
SUB tiraScheduleHeapReset

  tiraCheckActive ("tiraScheduleHeapReset")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_ASSIGN
  tiraCode$(t.LineCount) = "!G_MEM_TEMP_HEAP_PTR, !G_MEM_TEMP_START_PTR"
  t.LineCount = t.LineCount + 1

END SUB ' tiraScheduleHeapReset

''''''''''''''''''''''''
FUNCTION tiraScheduleShuntingOp (opVal AS LONG, valStack$(), valType() AS LONG, passValTop AS LONG)

  DIM resType AS LONG
  DIM opCmd AS LONG
  DIM t1 AS LONG
  DIM t2 AS LONG
  DIM isPow2 AS LONG
  DIM isConstRHS AS LONG
  DIM shiftAmt AS LONG
  DIM valCheck AS LONG
  DIM firstCh AS STRING * 1

  tiraCheckActive ("tiraScheduleShuntingOp")

  IF opVal = TOK_OP_UNARY_MINUS OR opVal = TOK_OP_UNARY_NOT THEN
    IF passValTop < 1 THEN
      throwCompilerError "MISSING OPERAND FOR UNARY", ASIS, 0
      tiraScheduleShuntingOp = 0
      EXIT FUNCTION
    END IF

    rhsVar$ = valStack$(passValTop - 1)
    resType = valType(passValTop - 1)

    resVar$ = tiraDimVar$("T", resType)

    IF opVal = TOK_OP_UNARY_MINUS THEN
      tiraOp TC_NEG, resVar$, rhsVar$, ""
    ELSE
      tiraOp TC_NOT, resVar$, rhsVar$, ""
    END IF

    valStack$(passValTop - 1) = resVar$

    return2 passValTop
    tiraScheduleShuntingOp = 1
    EXIT FUNCTION
  END IF

  IF passValTop < 2 THEN
    throwCompilerError "MISSING OPERAND FOR BINARY", ASIS, 0
    tiraScheduleShuntingOp = 0
    EXIT FUNCTION
  END IF

  rhsVar$ = valStack$(passValTop - 1)
  lhsVar$ = valStack$(passValTop - 2)

  t1 = valType(passValTop - 2)
  t2 = valType(passValTop - 1)

  IF opVal = TOK_OP_EQUAL OR opVal = TOK_OP_LESS OR opVal = TOK_OP_GREATER OR opVal = TOK_OP_LESS_EQUAL OR opVal = TOK_OP_GREATER_EQUAL OR opVal = TOK_OP_NOT_EQUAL THEN
    IF t1 = TYPE_STRING AND t2 <> TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH", ASIS, 0
      tiraScheduleShuntingOp = 0
      EXIT FUNCTION
    END IF
    IF t1 <> TYPE_STRING AND t2 = TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH", ASIS, 0
      tiraScheduleShuntingOp = 0
      EXIT FUNCTION
    END IF

    resType = TYPE_LONG
    resVar$ = tiraDimVar$("T", resType)

    condStr$ = "JE"

    SELECT CASE opVal

      CASE TOK_OP_EQUAL: condStr$ = "JE"
      CASE TOK_OP_LESS: condStr$ = "JL"
      CASE TOK_OP_GREATER: condStr$ = "JG"
      CASE TOK_OP_LESS_EQUAL: condStr$ = "JLE"
      CASE TOK_OP_GREATER_EQUAL: condStr$ = "JGE"
      CASE TOK_OP_NOT_EQUAL: condStr$ = "JNE"

    END SELECT ' opVal

    lblTrue$ = tiraLabelCreateNew$("REL_TRUE")
    lblEnd$ = tiraLabelCreateNew$("REL_END")

    tiraAssign resVar$, "0"
    tiraJmpCond condStr$, lhsVar$, rhsVar$, lblTrue$
    tiraJmp lblEnd$

    tiraLabel lblTrue$
    tiraAssign resVar$, "-1"

    tiraLabel lblEnd$

    valStack$(passValTop - 2) = resVar$
    valType(passValTop - 2) = resType
    passValTop = passValTop - 1

    return2 passValTop
    tiraScheduleShuntingOp = 1
    EXIT FUNCTION
  END IF

  IF t1 = TYPE_STRING AND t2 = TYPE_STRING THEN
    IF opVal = TOK_OP_PLUS THEN
      resType = TYPE_STRING
      opCmd = TC_CONCAT
    ELSE
      throwCompilerError "INVALID STRING OP", ASIS, 0
      tiraScheduleShuntingOp = 0
      EXIT FUNCTION
    END IF
  ELSE
    IF t1 = TYPE_STRING OR t2 = TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH", ASIS, 0
      tiraScheduleShuntingOp = 0
      EXIT FUNCTION
    END IF

    SELECT CASE opVal

      CASE TOK_OP_IDIV
        resType = TYPE_LONG

      CASE TOK_OP_POW
        resType = TYPE_DOUBLE

      CASE TOK_AND, TOK_OR
        resType = TYPE_LONG

      CASE ELSE
        resType = TYPE_LONG
        IF t1 = TYPE_INTEGER64 OR t2 = TYPE_INTEGER64 THEN resType = TYPE_INTEGER64
        IF t1 = TYPE_UINT64 OR t2 = TYPE_UINT64 THEN resType = TYPE_UINT64
        IF t1 = TYPE_SINGLE OR t2 = TYPE_SINGLE THEN resType = TYPE_SINGLE
        IF t1 = TYPE_DOUBLE OR t2 = TYPE_DOUBLE THEN resType = TYPE_DOUBLE
        IF opVal = TOK_OP_DIV THEN
          IF resType = TYPE_LONG THEN resType = TYPE_SINGLE
          IF resType = TYPE_INTEGER64 OR resType = TYPE_UINT64 THEN resType = TYPE_DOUBLE
        END IF

    END SELECT ' opVal

    SELECT CASE opVal

      CASE TOK_OP_PLUS: opCmd = TC_ADD
      CASE TOK_OP_MINUS: opCmd = TC_SUB
      CASE TOK_OP_MUL: opCmd = TC_MUL
      CASE TOK_OP_DIV: opCmd = TC_DIV
      CASE TOK_OP_IDIV: opCmd = TC_IDIV
      CASE TOK_OP_POW: opCmd = TC_POW
      CASE TOK_AND: opCmd = TC_AND
      CASE TOK_OR: opCmd = TC_OR

    END SELECT ' opVal

  END IF

  ' Speed optimization, convert constant power of two multiplication into a bitwise left shift
  IF opCmd = TC_MUL THEN
    ' Do not attempt to bitwise shift float mathematics!
    IF resType <> TYPE_SINGLE AND resType <> TYPE_DOUBLE THEN
      isPow2 = 0
      isConstRHS = 0
      shiftAmt = 0

      ' Try RHS
      firstCh = LEFT$(rhsVar$, 1)
      IF firstCh >= "0" AND firstCh <= "9" THEN
        valCheck = VAL(rhsVar$)

        SELECT CASE valCheck

          CASE 2: shiftAmt = 1: isPow2 = 1: isConstRHS = 1
          CASE 4: shiftAmt = 2: isPow2 = 1: isConstRHS = 1
          CASE 8: shiftAmt = 3: isPow2 = 1: isConstRHS = 1
          CASE 16: shiftAmt = 4: isPow2 = 1: isConstRHS = 1
          CASE 32: shiftAmt = 5: isPow2 = 1: isConstRHS = 1
          CASE 64: shiftAmt = 6: isPow2 = 1: isConstRHS = 1
          CASE 128: shiftAmt = 7: isPow2 = 1: isConstRHS = 1
          CASE 256: shiftAmt = 8: isPow2 = 1: isConstRHS = 1
          CASE 512: shiftAmt = 9: isPow2 = 1: isConstRHS = 1
          CASE 1024: shiftAmt = 10: isPow2 = 1: isConstRHS = 1
          CASE 2048: shiftAmt = 11: isPow2 = 1: isConstRHS = 1
          CASE 4096: shiftAmt = 12: isPow2 = 1: isConstRHS = 1

        END SELECT ' valCheck

      END IF

      ' Check LHS if the RHS operand was not a constant power of two
      IF isPow2 = 0 THEN
        firstCh = LEFT$(lhsVar$, 1)
        IF firstCh >= "0" AND firstCh <= "9" THEN
          valCheck = VAL(lhsVar$)

          SELECT CASE valCheck

            CASE 2: shiftAmt = 1: isPow2 = 1
            CASE 4: shiftAmt = 2: isPow2 = 1
            CASE 8: shiftAmt = 3: isPow2 = 1
            CASE 16: shiftAmt = 4: isPow2 = 1
            CASE 32: shiftAmt = 5: isPow2 = 1
            CASE 64: shiftAmt = 6: isPow2 = 1
            CASE 128: shiftAmt = 7: isPow2 = 1
            CASE 256: shiftAmt = 8: isPow2 = 1
            CASE 512: shiftAmt = 9: isPow2 = 1
            CASE 1024: shiftAmt = 10: isPow2 = 1
            CASE 2048: shiftAmt = 11: isPow2 = 1
            CASE 4096: shiftAmt = 12: isPow2 = 1

          END SELECT ' valCheck

        END IF
      END IF

      IF isPow2 = 1 THEN
        opCmd = TC_SHL
        IF isConstRHS = 1 THEN
          rhsVar$ = LTRIM$(STR$(shiftAmt))
        ELSE
          ' Swap so the variable is on the left
          lhsVar$ = rhsVar$
          rhsVar$ = LTRIM$(STR$(shiftAmt))
        END IF
      END IF
    END IF
  END IF

  resVar$ = tiraDimVar$("T", resType)
  tiraOp opCmd, resVar$, lhsVar$, rhsVar$

  valStack$(passValTop - 2) = resVar$
  valType(passValTop - 2) = resType
  passValTop = passValTop - 1

  return2 passValTop
  tiraScheduleShuntingOp = 1

END FUNCTION ' tiraScheduleShuntingOp

''''''''''''''''''''''''
SUB tiraScheduleSubEpilogue

  tiraCheckActive ("tiraScheduleSubEpilogue")

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM totalFrame AS LONG

  totalFrame = stack.consoleFrameSize

  IF currentSubName$ <> "" THEN
    ff = resolveSymbol(currentSubName$)
    IF ff = 1 THEN
      vIdx = returnedData2
      subIdx = symbols(vIdx).SubIndex
      IF subIdx <> 0 THEN
        totalFrame = totalFrame + subs(subIdx).LocalFrameSize
      END IF
    END IF
  END IF

  IF currentSubName$ <> "" THEN
    tiraAssign "!G_MEM_TEMP_HEAP_PTR", "!G_MEM_TEMP_START_PTR"
    tiraAssign "!G_MEM_TEMP_START_PTR", "~HEAP_SAVE"
  END IF

  tiraNew TC_LEAVE_FRAME, cTrNum$(totalFrame)

END SUB ' tiraScheduleSubEpilogue

''''''''''''''''''''''''
SUB tiraScheduleSubPrologue

  tiraCheckActive ("tiraScheduleSubPrologue")

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM totalFrame AS LONG

  totalFrame = stack.consoleFrameSize

  IF currentSubName$ <> "" THEN
    ff = resolveSymbol(currentSubName$)
    IF ff = 1 THEN
      vIdx = returnedData2
      subIdx = symbols(vIdx).SubIndex
      IF subIdx <> 0 THEN
        subs(subIdx).ExitPatchList = 0 ' Initialize the Exit Patch List

        ff = resolveSymbol("~HEAP_SAVE")
        IF ff = 1 THEN
          symbols(returnedData2).DataType = TYPE_INTEGER64
        END IF

        totalFrame = totalFrame + subs(subIdx).LocalFrameSize
      END IF
    END IF
  END IF

  framePtr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_ENTER_FRAME, cTrNum$(totalFrame) + ", " + framePtr$

  ' Zero out the local stack frame to prevent garbage data from causing issues
  tiraMemSet framePtr$, "0", cTrNum$(totalFrame)

  IF currentSubName$ <> "" THEN
    tiraAssign "~HEAP_SAVE", "!G_MEM_TEMP_START_PTR"
    tiraAssign "!G_MEM_TEMP_START_PTR", "!G_MEM_TEMP_HEAP_PTR"
  END IF

END SUB ' tiraScheduleSubPrologue

''''''''''''''''''''''''
SUB tiraSetSubOffset (subIdx AS LONG)

  tiraCheckActive ("tiraSetSubOffset")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_SET_SUB_OFFSET
  tiraCode$(t.LineCount) = LTRIM$(STR$(subIdx))
  t.LineCount = t.LineCount + 1

END SUB ' tiraSetSubOffset

''''''''''''''''''''''''
FUNCTION tiraStackVar$ (baseName$, wDataType AS LONG, wOffset AS LONG)

  tiraCheckActive ("tiraStackVar$")

  DIM vIdx AS LONG

  SELECT CASE wDataType

    CASE TYPE_STRING: typePrefix$ = "TSTR_"
    CASE TYPE_SINGLE: typePrefix$ = "TSNG_"
    CASE TYPE_DOUBLE: typePrefix$ = "TDBL_"
    CASE TYPE_BYTE: typePrefix$ = "TBYT_"
    CASE TYPE_UBYTE: typePrefix$ = "TUBY_"
    CASE TYPE_INTEGER: typePrefix$ = "TINT_"
    CASE TYPE_UINTEGER: typePrefix$ = "TUIN_"
    CASE TYPE_LONG: typePrefix$ = "TLNG_"
    CASE TYPE_ULONG: typePrefix$ = "TULN_"
    CASE TYPE_INTEGER64: typePrefix$ = "TI64_"
    CASE TYPE_UINT64: typePrefix$ = "TU64_"
    CASE TYPE_UDT: typePrefix$ = "TUDT_"
    CASE ELSE: typePrefix$ = "TUNK_"

  END SELECT ' wDataType

  tempName$ = "~" + typePrefix$ + "WND_" + baseName$ + "_" + LTRIM$(RTRIM$(STR$(t.TempCounter)))
  t.TempCounter = t.TempCounter + 1

  ff = resolveSymbol(tempName$)
  IF ff = 1 THEN
    vIdx = returnedData2
    symbols(vIdx).DataType = wDataType
    symbols(vIdx).IsLocal = LOCAL_ABSOLUTE
    symbols(vIdx).LocalOffset = wOffset - stack.GFX_WNDPROC_FRAME
  END IF

  tiraStackVar$ = tempName$

END FUNCTION ' tiraStackVar$

''''''''''''''''''''''''
SUB tiraSwapMem (addr1$, addr2$, sizeMode$)

  tiraCheckActive ("tiraSwapMem")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_SWAP_MEM
  tiraCode$(t.LineCount) = addr1$ + ", " + addr2$ + ", " + sizeMode$
  t.LineCount = t.LineCount + 1

END SUB ' tiraSwapMem

''''''''''''''''''''''''
FUNCTION tiraWndVar$ (baseName$, wDataType AS LONG)

  tiraCheckActive ("tiraWndVar$")

  DIM vIdx AS LONG

  SELECT CASE wDataType

    CASE TYPE_STRING: typePrefix$ = "TSTR_"
    CASE TYPE_SINGLE: typePrefix$ = "TSNG_"
    CASE TYPE_DOUBLE: typePrefix$ = "TDBL_"
    CASE TYPE_BYTE: typePrefix$ = "TBYT_"
    CASE TYPE_UBYTE: typePrefix$ = "TUBY_"
    CASE TYPE_INTEGER: typePrefix$ = "TINT_"
    CASE TYPE_UINTEGER: typePrefix$ = "TUIN_"
    CASE TYPE_LONG: typePrefix$ = "TLNG_"
    CASE TYPE_ULONG: typePrefix$ = "TULN_"
    CASE TYPE_INTEGER64: typePrefix$ = "TI64_"
    CASE TYPE_UINT64: typePrefix$ = "TU64_"
    CASE TYPE_UDT: typePrefix$ = "TUDT_"
    CASE ELSE: typePrefix$ = "TUNK_"

  END SELECT ' wDataType

  ' Creates a highly readable, SSA-safe ephemeral variable name specifically for WndProc
  ' We use WND_ as the prefix to physically separate the memory slot from Thread 2's T_ namespace
  tempName$ = "~" + typePrefix$ + "WND_" + baseName$ + "_" + LTRIM$(RTRIM$(STR$(t.TempCounter)))
  t.TempCounter = t.TempCounter + 1

  ff = resolveSymbol(tempName$)
  IF ff = 1 THEN
    vIdx = returnedData2
    symbols(vIdx).DataType = wDataType
  END IF

  tiraWndVar$ = tempName$

END FUNCTION ' tiraWndVar$

''''''''''''''''''''''''
SUB tiraWriteMem (destAddr$, srcVal$, sizeMode$)

  tiraCheckActive ("tiraWriteMem")
  IF tiraLineCheck THEN EXIT SUB

  tiraCmd(t.LineCount) = TC_WRITE_MEM
  tiraCode$(t.LineCount) = destAddr$ + ", " + srcVal$ + ", " + sizeMode$
  t.LineCount = t.LineCount + 1

END SUB ' tiraWriteMem

''''''''''''''''''''''''
SUB tokenizeLine (wLine$)

  lineTokenCount = 0
  lineLen = LEN(wLine$)
  ix = 1

  DO WHILE ix <= lineLen
    ch$ = MID$(wLine$, ix, 1)

    SELECT CASE ch$

      CASE "'"
        remText$ = UCASE$(LTRIM$(MID$(wLine$, ix + 1)))
        IF LEFT$(remText$, 7) = "$STATIC" THEN
          IF lineTokenCount < MAX_TOKENS THEN
            lineTokens$(lineTokenCount) = CHR$(TOK_STATIC \ 256) + CHR$(TOK_STATIC AND 255)
            lineTokenVals(lineTokenCount) = TOK_STATIC
            lineTokenCount = lineTokenCount + 1
          END IF
        ELSE
          IF LEFT$(remText$, 8) = "$DYNAMIC" THEN
            IF lineTokenCount < MAX_TOKENS THEN
              lineTokens$(lineTokenCount) = CHR$(TOK_DYNAMIC \ 256) + CHR$(TOK_DYNAMIC AND 255)
              lineTokenVals(lineTokenCount) = TOK_DYNAMIC
              lineTokenCount = lineTokenCount + 1
            END IF
          END IF
        END IF
        EXIT DO

      CASE " ", CHR$(9)
        ix = ix + 1

      CASE "0" TO "9", "."
        isNum = 0
        IF ch$ = "." THEN
          IF ix < lineLen THEN
            chNext$ = MID$(wLine$, ix + 1, 1)
            IF chNext$ >= "0" AND chNext$ <= "9" THEN isNum = 1
          END IF
        ELSE
          isNum = 1
        END IF

        IF isNum = 1 THEN
          numVal$ = ""
          hasDecimal = 0
          DO WHILE ix <= lineLen
            ch2$ = MID$(wLine$, ix, 1)
            IF ch2$ >= "0" AND ch2$ <= "9" THEN
              numVal$ = numVal$ + ch2$
              ix = ix + 1
            ELSE
              IF ch2$ = "." AND hasDecimal = 0 THEN
                hasDecimal = 1
                numVal$ = numVal$ + ch2$
                ix = ix + 1
              ELSE
                EXIT DO
              END IF
            END IF
          LOOP

          IF ix <= lineLen THEN
            ch2$ = MID$(wLine$, ix, 1)
            IF ch2$ = "#" OR ch2$ = "!" OR ch2$ = "&" OR ch2$ = "%" THEN
              numVal$ = numVal$ + ch2$
              ix = ix + 1
            END IF
          END IF

          IF ix <= lineLen THEN
            ch2$ = MID$(wLine$, ix, 1)
            IF (ch2$ >= "A" AND ch2$ <= "Z") OR (ch2$ >= "a" AND ch2$ <= "z") OR ch2$ = "_" THEN
              chunkStart = ix - LEN(numVal$)
              DO WHILE chunkStart > 1
                chPrev$ = MID$(wLine$, chunkStart - 1, 1)
                IF chPrev$ = " " OR chPrev$ = CHR$(9) THEN EXIT DO
                chunkStart = chunkStart - 1
              LOOP
              chunkEnd = ix
              DO WHILE chunkEnd <= lineLen
                chNext$ = MID$(wLine$, chunkEnd, 1)
                IF chNext$ = " " OR chNext$ = CHR$(9) THEN EXIT DO
                chunkEnd = chunkEnd + 1
              LOOP
              chunkStr$ = MID$(wLine$, chunkStart, chunkEnd - chunkStart)
              throwCompilerError "UNRECOGNIZED KEYWORD: " + chunkStr$, ASIS, 0
              EXIT SUB
            END IF
          END IF

          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = numVal$
          lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
          lineTokenCount = lineTokenCount + 1
        ELSE
          symVal = 256 + ASC(ch$)
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
          lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
          lineTokenCount = lineTokenCount + 1
          ix = ix + 1
        END IF

      CASE "&"
        IF ix < lineLen THEN
          ch2$ = UCASE$(MID$(wLine$, ix + 1, 1))
          IF ch2$ = "H" THEN
            hexStr$ = "&H"
            ix = ix + 2
            DO WHILE ix <= lineLen
              ch3$ = UCASE$(MID$(wLine$, ix, 1))
              IF (ch3$ >= "0" AND ch3$ <= "9") OR (ch3$ >= "A" AND ch3$ <= "F") THEN
                hexStr$ = hexStr$ + ch3$
                ix = ix + 1
              ELSE
                EXIT DO
              END IF
            LOOP
            numVal$ = LTRIM$(RTRIM$(STR$(VAL(hexStr$))))
            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = numVal$
            lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
            lineTokenCount = lineTokenCount + 1
          ELSE
            symVal = 256 + ASC(ch$)
            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
            lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
            lineTokenCount = lineTokenCount + 1
            ix = ix + 1
          END IF
        ELSE
          symVal = 256 + ASC(ch$)
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
          lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
          lineTokenCount = lineTokenCount + 1
          ix = ix + 1
        END IF

      CASE "-"
        IF ix < lineLen THEN
          ch2$ = MID$(wLine$, ix + 1, 1)
          isNum = 0
          IF ch2$ >= "0" AND ch2$ <= "9" THEN isNum = 1
          IF ch2$ = "." THEN
            IF ix + 1 < lineLen THEN
              ch3$ = MID$(wLine$, ix + 2, 1)
              IF ch3$ >= "0" AND ch3$ <= "9" THEN isNum = 1
            END IF
          END IF

          IF isNum = 1 THEN
            numVal$ = "-"
            ix = ix + 1
            hasDecimal = 0
            DO WHILE ix <= lineLen
              ch3$ = MID$(wLine$, ix, 1)
              IF ch3$ >= "0" AND ch3$ <= "9" THEN
                numVal$ = numVal$ + ch3$
                ix = ix + 1
              ELSE
                IF ch3$ = "." AND hasDecimal = 0 THEN
                  hasDecimal = 1
                  numVal$ = numVal$ + ch3$
                  ix = ix + 1
                ELSE
                  EXIT DO
                END IF
              END IF
            LOOP

            IF ix <= lineLen THEN
              ch3$ = MID$(wLine$, ix, 1)
              IF ch3$ = "#" OR ch3$ = "!" OR ch3$ = "&" OR ch3$ = "%" THEN
                numVal$ = numVal$ + ch3$
                ix = ix + 1
              END IF
            END IF

            IF ix <= lineLen THEN
              ch2$ = MID$(wLine$, ix, 1)
              IF (ch2$ >= "A" AND ch2$ <= "Z") OR (ch2$ >= "a" AND ch2$ <= "z") OR ch2$ = "_" THEN
                chunkStart = ix - LEN(numVal$)
                DO WHILE chunkStart > 1
                  chPrev$ = MID$(wLine$, chunkStart - 1, 1)
                  IF chPrev$ = " " OR chPrev$ = CHR$(9) THEN EXIT DO
                  chunkStart = chunkStart - 1
                LOOP
                chunkEnd = ix
                DO WHILE chunkEnd <= lineLen
                  chNext$ = MID$(wLine$, chunkEnd, 1)
                  IF chNext$ = " " OR chNext$ = CHR$(9) THEN EXIT DO
                  chunkEnd = chunkEnd + 1
                LOOP
                chunkStr$ = MID$(wLine$, chunkStart, chunkEnd - chunkStart)
                throwCompilerError "UNRECOGNIZED KEYWORD: " + chunkStr$, ASIS, 0
                EXIT SUB
              END IF
            END IF

            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = numVal$
            lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
            lineTokenCount = lineTokenCount + 1
          ELSE
            symVal = 256 + ASC(ch$)
            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
            lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
            lineTokenCount = lineTokenCount + 1
            ix = ix + 1
          END IF
        ELSE
          symVal = 256 + ASC(ch$)
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
          lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
          lineTokenCount = lineTokenCount + 1
          ix = ix + 1
        END IF

      CASE CHR$(34)
        strVal$ = CHR$(34)
        ix = ix + 1
        hasEndQuote = 0
        DO WHILE ix <= lineLen
          ch2$ = MID$(wLine$, ix, 1)
          strVal$ = strVal$ + ch2$
          ix = ix + 1
          IF ch2$ = CHR$(34) THEN
            hasEndQuote = 1
            EXIT DO
          END IF
        LOOP
        IF hasEndQuote = 0 THEN
          throwCompilerError "MISSING END QUOTE", ASIS, 0
          EXIT SUB
        END IF
        IF lineTokenCount >= MAX_TOKENS THEN
          throwCompilerError "TOKEN LIMIT", ASIS, 0
          EXIT SUB
        END IF
        lineTokens$(lineTokenCount) = strVal$
        lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
        lineTokenCount = lineTokenCount + 1

      CASE "#"
        identVal$ = "#"
        ix = ix + 1
        DO WHILE ix <= lineLen
          ch2$ = MID$(wLine$, ix, 1)
          u2$ = UCASE$(ch2$)
          IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") THEN
            identVal$ = identVal$ + ch2$
            ix = ix + 1
          ELSE
            EXIT DO
          END IF
        LOOP

        uIdent$ = UCASE$(identVal$)
        isKey = 0
        kwVal = 0
        FOR ii = 512 TO 1023
          IF voc(ii).text <> "" THEN
            IF uIdent$ = voc(ii).text THEN
              isKey = 1
              kwVal = ii
              EXIT FOR
            END IF
          END IF
        NEXT

        IF lineTokenCount >= MAX_TOKENS THEN
          throwCompilerError "TOKEN LIMIT", ASIS, 0
          EXIT SUB
        END IF
        IF isKey = 1 THEN
          lineTokens$(lineTokenCount) = CHR$(kwVal \ 256) + CHR$(kwVal AND 255)
        ELSE
          lineTokens$(lineTokenCount) = identVal$
        END IF
        lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
        lineTokenCount = lineTokenCount + 1

      CASE "$"
        identVal$ = "$"
        ix = ix + 1
        DO WHILE ix <= lineLen
          ch2$ = MID$(wLine$, ix, 1)
          u2$ = UCASE$(ch2$)
          IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") THEN
            identVal$ = identVal$ + ch2$
            ix = ix + 1
          ELSE
            EXIT DO
          END IF
        LOOP

        uIdent$ = UCASE$(identVal$)
        isKey = 0
        kwVal = 0
        FOR ii = 512 TO 1023
          IF voc(ii).text <> "" THEN
            IF uIdent$ = voc(ii).text THEN
              isKey = 1
              kwVal = ii
              EXIT FOR
            END IF
          END IF
        NEXT

        IF lineTokenCount >= MAX_TOKENS THEN
          throwCompilerError "TOKEN LIMIT", ASIS, 0
          EXIT SUB
        END IF
        IF isKey = 1 THEN
          lineTokens$(lineTokenCount) = CHR$(kwVal \ 256) + CHR$(kwVal AND 255)
        ELSE
          lineTokens$(lineTokenCount) = identVal$
        END IF
        lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
        lineTokenCount = lineTokenCount + 1

      CASE "A" TO "Z", "a" TO "z", "_"
        identVal$ = ""
        DO WHILE ix <= lineLen
          ch2$ = MID$(wLine$, ix, 1)
          u2$ = UCASE$(ch2$)
          IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") OR ch2$ = "_" THEN
            identVal$ = identVal$ + ch2$
            ix = ix + 1
          ELSE
            EXIT DO
          END IF
        LOOP

        IF ix <= lineLen THEN
          ch2$ = MID$(wLine$, ix, 1)
          IF ch2$ = "$" OR ch2$ = "#" OR ch2$ = "!" OR ch2$ = "&" OR ch2$ = "%" THEN
            identVal$ = identVal$ + ch2$
            ix = ix + 1
          END IF
        END IF

        uIdent$ = UCASE$(identVal$)

        IF uIdent$ = "REM" THEN
          remText$ = UCASE$(LTRIM$(MID$(wLine$, ix)))
          IF LEFT$(remText$, 7) = "$STATIC" THEN
            IF lineTokenCount < MAX_TOKENS THEN
              lineTokens$(lineTokenCount) = CHR$(TOK_STATIC \ 256) + CHR$(TOK_STATIC AND 255)
              lineTokenVals(lineTokenCount) = TOK_STATIC
              lineTokenCount = lineTokenCount + 1
            END IF
          ELSE
            IF LEFT$(remText$, 8) = "$DYNAMIC" THEN
              IF lineTokenCount < MAX_TOKENS THEN
                lineTokens$(lineTokenCount) = CHR$(TOK_DYNAMIC \ 256) + CHR$(TOK_DYNAMIC AND 255)
                lineTokenVals(lineTokenCount) = TOK_DYNAMIC
                lineTokenCount = lineTokenCount + 1
              END IF
            END IF
          END IF
          EXIT DO
        END IF

        uIdentSearch$ = uIdent$
        IF uIdentSearch$ = "_BYTE" THEN uIdentSearch$ = "BYTE"
        IF uIdentSearch$ = "_INTEGER" THEN uIdentSearch$ = "INTEGER"
        IF uIdentSearch$ = "_LONG" THEN uIdentSearch$ = "LONG"
        IF uIdentSearch$ = "_INTEGER64" THEN uIdentSearch$ = "INTEGER64"
        IF uIdentSearch$ = "_SINGLE" THEN uIdentSearch$ = "SINGLE"
        IF uIdentSearch$ = "_DOUBLE" THEN uIdentSearch$ = "DOUBLE"
        IF uIdentSearch$ = "_STRING" THEN uIdentSearch$ = "STRING"
        IF uIdentSearch$ = "_UNSIGNED" THEN uIdentSearch$ = "UNSIGNED"
        IF uIdentSearch$ = "_ANY" THEN uIdentSearch$ = "ANY"

        isKey = 0
        kwVal = 0
        FOR ii = 512 TO 1023
          IF voc(ii).text <> "" THEN
            IF uIdentSearch$ = voc(ii).text THEN
              isKey = 1
              kwVal = ii
              EXIT FOR
            END IF
          END IF
        NEXT

        IF lineTokenCount >= MAX_TOKENS THEN
          throwCompilerError "TOKEN LIMIT", ASIS, 0
          EXIT SUB
        END IF
        IF isKey = 1 THEN
          lineTokens$(lineTokenCount) = CHR$(kwVal \ 256) + CHR$(kwVal AND 255)
        ELSE
          lineTokens$(lineTokenCount) = identVal$
        END IF
        lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
        lineTokenCount = lineTokenCount + 1

      CASE ELSE
        isPascalAssign = 0
        IF ch$ = ":" AND compileEmeraldMode = 1 THEN
          IF ix < lineLen THEN
            chNext$ = MID$(wLine$, ix + 1, 1)
            IF chNext$ = "=" THEN
              isPascalAssign = 1
            END IF
          END IF
        END IF

        IF isPascalAssign = 1 THEN
          symVal = 256 + ASC("=")
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
          lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
          lineTokenCount = lineTokenCount + 1
          ix = ix + 2
        ELSE
          symVal = 256 + ASC(ch$)
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
          lineTokenVals(lineTokenCount) = retTokenVal(lineTokens$(lineTokenCount))
          lineTokenCount = lineTokenCount + 1
          ix = ix + 1
        END IF

    END SELECT ' ch$

  LOOP

END SUB ' tokenizeLine

''''''''''''''''''''''''
SUB undo_StateRestore

  IF undoState.Ready = 0 THEN EXIT SUB

  FOR ii = 1 TO undoState.LastLine
    editorText$(ii) = undoText$(ii)
  NEXT
  FOR ii = undoState.LastLine + 1 TO editor.LastLine
    editorText$(ii) = ""
  NEXT

  editor.CursorX = undoState.CursorX
  editor.CursorY = undoState.CursorY
  editor.ScrollX = undoState.ScrollX
  editor.ScrollY = undoState.ScrollY
  editor.LastLine = undoState.LastLine

  undoState.Ready = 0
  lastActionWasTyping = 0

  addStatusMsg "UNDO USED"

  refineCode (0)

END SUB ' undo_StateRestore

''''''''''''''''''''''''
SUB undo_StateSave

  FOR ii = 1 TO editor.LastLine
    undoText$(ii) = editorText$(ii)
  NEXT
  FOR ii = editor.LastLine + 1 TO undoState.LastLine
    undoText$(ii) = ""
  NEXT

  undoState.CursorX = editor.CursorX
  undoState.CursorY = editor.CursorY
  undoState.ScrollX = editor.ScrollX
  undoState.ScrollY = editor.ScrollY
  undoState.LastLine = editor.LastLine

  undoState.Ready = 1

END SUB ' undo_StateSave

''''''''''''''''''''''''
FUNCTION updateStackAlignment

  ' Check for minimum 4-byte alignment (bits 0 and 1 must be 0)
  IF (stack.currentStackOffset AND 3) <> 0 THEN
    ESCAPETEXT "STACK MISALIGNMENT: RSP not 4-byte aligned ($" + hexLen$(stack.currentStackOffset, 8) + ")"
  END IF

  IF (stack.currentStackOffset AND 8) = 0 THEN
    stack.stackIs16Aligned = 1
  ELSE
    stack.stackIs16Aligned = 0
  END IF

  updateStackAlignment = stack.stackIs16Aligned

END FUNCTION ' updateStackAlignment

''''''''''''''''''''''''
FUNCTION verifyNoExtraTokens (passEndIdx, passExpectedEndIdx, passCommandName$)

  tempRet = 1

  IF passEndIdx > passExpectedEndIdx THEN
    throwCompilerError "UNEXPECTED TOKEN AFTER " + passCommandName$, ASIS, 0
    tempRet = 0
  END IF

  verifyNoExtraTokens = tempRet

END FUNCTION ' verifyNoExtraTokens

''''''''''''''''''''''''
SUB viewSubsModal

  DIM localScrollY AS LONG
  DIM localDragActive AS LONG
  DIM localDragOffset AS LONG

  localScrollY = 0
  localDragActive = 0
  localDragOffset = 0

  ' Ensure the sub list is completely fresh
  refineCode (0)

  DO
    limitSpeed
    mouseReadInput

    redrawAll

    boxW = 200
    boxH = 240
    boxX = (SCREENSIZEX - boxW) \ 2
    boxY = (SCREENSIZEY - boxH) \ 2

    drawBorderBox boxX, boxY, boxW, boxH, 15, editor.windowBarClr

    closeBtnW = 15
    closeBtnH = 13
    closeBtnX = boxX + boxW - closeBtnW
    closeBtnY = boxY
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, 0, 1

    IF mouseClickedInBox(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
      EXIT DO
    END IF

    PrintStr boxX + (boxW \ 2) - (15 * 4), boxY + 3, "SUBS / FUNCTIONS", 14, 0, 1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    itemH = 10
    maxLines = (boxH - 15) \ itemH

    ' Scrollbar
    scrollBarX = boxX + boxW - 12
    scrollBarY = boxY + 14
    scrollBarW = 12
    scrollBarH = boxH - 15

    localScrollY = processVScrollbar(scrollBarX, scrollBarY, scrollBarW, scrollBarH, uiSubCount, maxLines, localScrollY, localDragActive, localDragOffset, 0)
    localDragActive = returnedData2
    localDragOffset = returnedData3

    ' Mouse wheel
    IF mouse.Wheel <> 0 THEN
      IF mouseWithinBoxBounds(boxX, boxY, boxW, boxH) THEN
        localScrollY = localScrollY + mouse.Wheel
        maxScroll = uiSubCount - maxLines
        IF maxScroll < 0 THEN maxScroll = 0
        IF localScrollY > maxScroll THEN localScrollY = maxScroll
        IF localScrollY < 0 THEN localScrollY = 0
      END IF
    END IF

    ' Draw items
    FOR ii = 0 TO maxLines - 1
      subIdx = ii + localScrollY
      IF subIdx < uiSubCount THEN
        itemY = boxY + 14 + (ii * itemH)
        sOutName$ = uiSubName$(subIdx)

        ' Hover
        IF mouseWithinBoxBounds(boxX + 2, itemY, boxW - 16, itemH) THEN
          drawClearBox boxX + 2, itemY, boxW - 16, itemH, 9

          IF mouseClickedInBox(boxX + 2, itemY, boxW - 16, itemH) THEN
            ' Update main UI funcScrollY to ensure right-hand list brings the sub into view
            IF subIdx < funcScrollY OR subIdx >= funcScrollY + 12 THEN
              funcScrollY = subIdx - 5
              IF funcScrollY < 0 THEN funcScrollY = 0
              maxFuncScroll = uiSubCount - 12
              IF maxFuncScroll < 0 THEN maxFuncScroll = 0
              IF funcScrollY > maxFuncScroll THEN funcScrollY = maxFuncScroll
              ' Redraw the right list so it reflects the new scroll position
              drawFuncListPMI
            END IF

            ' Flash the right-hand box list simultaneously
            funcListBoxX = RIGHT_BOX_X
            funcListBoxY = editor.StartY
            funcListBoxW = 122
            rowY = funcListBoxY + 3 + ((subIdx - funcScrollY + 1) * 10)
            LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 11, rowY + 9), 1, BF
            PrintStr funcListBoxX + RIGHT_BOX_SPACING, rowY + 1, LEFT$(uiSubName$(subIdx), 13), 15, 0, 1

            ' Flash the modal list
            LINE (boxX + 2, itemY)-(boxX + boxW - 15, itemY + itemH - 1), 1, BF
            PrintStr boxX + 8, itemY + 1, sOutName$, 15, 0, 1

            _DISPLAY
            waitTimer UI_FLASH_TIME

            ' Jump to sub and close window
            editor.CursorY = uiSubLine(subIdx)
            editor.CursorX = 0
            editor.ScrollY = editor.CursorY - 14
            IF editor.ScrollY < 1 THEN editor.ScrollY = 1
            editor.ScrollX = 0
            editor.SelectStartX = 0
            editor.SelectStartY = 1
            editor.IsSelecting = 0
            editor.Focus = 1

            EXIT DO
          END IF
        END IF

        PrintStr boxX + 8, itemY + 1, sOutName$, 11, 0, 1
      END IF
    NEXT

    _DISPLAY

    kVal = keyCheck("ESC")
    IF kVal = 27 THEN
      waitKeyRelease "ESC"
      EXIT DO
    END IF

  LOOP

END SUB ' viewSubsModal

''''''''''''''''''''''''
SUB waitKeyRelease (wKey$)

  _DISPLAY ' _DISPLAY statements can mess with visual output without a _DISPLAY after, so we'll run the command one more time

  DO
  LOOP UNTIL keyCheck(wKey$) = 0

END SUB ' waitKeyRelease

''''''''''''''''''''''''
SUB waitTimer (wSeconds)

  tGoal = TIMER + wSeconds
  DO WHILE TIMER < tGoal
  LOOP

END SUB ' waitTimer

''''''''''''''''''''''''
SUB writeIdataSection (wTextRawSize)

  '''' Import Directory Table
  FOR iDll = 0 TO impTbl.numDlls - 1
    arrayWrite32LE impDlls(iDll).IltRVA
    arrayWrite32LE 0
    arrayWrite32LE 0
    arrayWrite32LE impDlls(iDll).NameRVA
    arrayWrite32LE impDlls(iDll).IatRVA
  NEXT

  '''' Null descriptor
  arrayPadNumBytes 20, 0

  '''' ILTs
  FOR iDll = 0 TO impTbl.numDlls - 1
    FOR iFunc = 0 TO impDlls(iDll).FuncCount - 1
      arrayWrite32LE impFuncs(iDll, iFunc).FuncRVA
      arrayWrite32LE 0
    NEXT
    arrayWrite32LE 0
    arrayWrite32LE 0
  NEXT

  '''' IATs
  FOR iDll = 0 TO impTbl.numDlls - 1
    FOR iFunc = 0 TO impDlls(iDll).FuncCount - 1
      arrayWrite32LE impFuncs(iDll, iFunc).FuncRVA
      arrayWrite32LE 0
    NEXT
    arrayWrite32LE 0
    arrayWrite32LE 0
  NEXT

  '''' Hint/name table
  FOR iDll = 0 TO impTbl.numDlls - 1
    FOR iFunc = 0 TO impDlls(iDll).FuncCount - 1
      outputFile(outputFileIdx) = 0
      outputFileIdx = outputFileIdx + 1
      outputFile(outputFileIdx) = 0
      outputFileIdx = outputFileIdx + 1

      fName$ = RTRIM$(impFuncs(iDll, iFunc).FuncName)
      FOR ii = 1 TO LEN(fName$)
        outputFile(outputFileIdx) = ASC(MID$(fName$, ii, 1))
        outputFileIdx = outputFileIdx + 1
      NEXT
      outputFile(outputFileIdx) = 0
      outputFileIdx = outputFileIdx + 1

      nameLen = LEN(fName$) + 1
      entrySize = 2 + nameLen
      IF (entrySize AND 1) <> 0 THEN
        outputFile(outputFileIdx) = 0
        outputFileIdx = outputFileIdx + 1
      END IF
    NEXT
  NEXT

  '''' DLL names
  FOR iDll = 0 TO impTbl.numDlls - 1
    dName$ = RTRIM$(impDlls(iDll).DllName)
    FOR ii = 1 TO LEN(dName$)
      outputFile(outputFileIdx) = ASC(MID$(dName$, ii, 1))
      outputFileIdx = outputFileIdx + 1
    NEXT
    outputFile(outputFileIdx) = 0
    outputFileIdx = outputFileIdx + 1

    nameLen = LEN(dName$) + 1
    IF (nameLen AND 1) <> 0 THEN
      outputFile(outputFileIdx) = 0
      outputFileIdx = outputFileIdx + 1
    END IF
  NEXT

  ' Pad .idata section to final size
  arrayPadUpTo PE_FILE_HEADER_OFFSET + wTextRawSize + impTbl.idataRawSize, 0

END SUB ' writeIdataSection

''''''''''''''''''''''''
SUB writePEHeader (wTextRawSize)

  localIdataFileOffset = PE_FILE_HEADER_OFFSET + wTextRawSize
  localIdataEndOffset = localIdataFileOffset + impTbl.idataRawSize

  '''' Dos mz header
  outputFile(outputFileIdx) = ASC("M"): outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = ASC("Z"): outputFileIdx = outputFileIdx + 1

  arrayPadNumBytes 58, 0

  arrayWrite32LE &H00000040 ' e_lfanew: PE header offset

  '''' Pe signature
  outputFile(outputFileIdx) = ASC("P"): outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = ASC("E"): outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1

  '''' Coff file header
  arrayWrite16LE PE_MACHINE_AMD64 ' Machine
  arrayWrite16LE PE_NUM_SECTIONS ' NumberOfSections
  arrayWrite32LE &H00000000 ' TimeDateStamp
  arrayWrite32LE &H00000000 ' PointerToSymbolTable
  arrayWrite32LE &H00000000 ' NumberOfSymbols
  arrayWrite16LE PE_OPT_HEADER_SIZE ' SizeOfOptionalHeader
  arrayWrite16LE &H0002 ' Characteristics: executable image

  '''' Optional header pe32+
  arrayWrite16LE PE_MAGIC_PE32PLUS ' Magic
  arrayWrite16LE &H000E ' MajorLinkerVersion, MinorLinkerVersion
  arrayWrite32LE wTextRawSize ' SizeOfCode
  arrayWrite32LE impTbl.idataRawSize ' SizeOfInitializedData
  arrayWrite32LE &H00000000 ' SizeOfUninitializedData
  arrayWrite32LE PE_TEXT_RVA ' AddressOfEntryPoint (.text start)
  arrayWrite32LE PE_TEXT_RVA ' BaseOfCode
  arrayWrite32LE PE_IMAGE_BASE ' ImageBase
  arrayWrite32LE &H00000000 ' SectionAlignment high dword (qword pair)
  arrayWrite32LE PE_SECTION_ALIGNMENT ' SectionAlignment
  arrayWrite32LE PE_FILE_ALIGNMENT ' FileAlignment
  arrayWrite16LE &H0006 ' MajorOperatingSystemVersion
  arrayWrite16LE &H0000 ' MinorOperatingSystemVersion
  arrayWrite16LE &H0000 ' MajorImageVersion
  arrayWrite16LE &H0000 ' MinorImageVersion
  arrayWrite16LE &H0006 ' MajorSubsystemVersion
  arrayWrite16LE &H0000 ' MinorSubsystemVersion
  arrayWrite32LE &H00000000 ' Win32VersionValue
  unroundedSum = impTbl.baseRVA + (localIdataEndOffset - localIdataFileOffset)
  roundedImageSize = ((unroundedSum + PE_SECTION_ALIGNMENT - 1) \ PE_SECTION_ALIGNMENT) * PE_SECTION_ALIGNMENT
  arrayWrite32LE roundedImageSize ' SizeOfImage
  arrayWrite32LE PE_FILE_ALIGNMENT ' SizeOfHeaders
  arrayWrite32LE &H00000000 ' CheckSum

  IF compileHasGraphics = 1 THEN
    arrayWrite16LE &H0002 ' Subsystem: GUI (Windows)
  ELSE
    arrayWrite16LE &H0003 ' Subsystem: console
  END IF

  arrayWrite16LE &H8100 ' DllCharacteristics: NX compat, no SEH
  arrayWrite32LE &H00100000 ' SizeOfStackReserve low dword
  arrayWrite32LE &H00000000 ' SizeOfStackReserve high dword
  arrayWrite32LE &H00001000 ' SizeOfStackCommit low dword
  arrayWrite32LE &H00000000 ' SizeOfStackCommit high dword
  arrayWrite32LE &H00100000 ' SizeOfHeapReserve low dword
  arrayWrite32LE &H00000000 ' SizeOfHeapReserve high dword
  arrayWrite32LE &H00001000 ' SizeOfHeapCommit low dword
  arrayWrite32LE &H00000000 ' SizeOfHeapCommit high dword
  arrayWrite32LE &H00000000 ' LoaderFlags
  arrayWrite32LE &H00000010 ' NumberOfRvaAndSizes
  arrayWrite32LE &H00000000 ' DataDirectory[0] Export table RVA
  arrayWrite32LE &H00000000 ' DataDirectory[0] Export table size
  arrayWrite32LE impTbl.baseRVA ' DataDirectory[1] Import table RVA
  arrayWrite32LE impTbl.idtSize ' DataDirectory[1] Import table size
  arrayPadNumBytes 80, 0 ' DataDirectory[2..8]: unused entries
  arrayWrite32LE impDlls(0).IatRVA ' DataDirectory[12] IAT RVA
  arrayWrite32LE impTbl.totalIatSize ' DataDirectory[12] IAT size
  arrayPadNumBytes 24, 0 ' DataDirectory[13..15]: unused entries

  '''' Section table - .text
  arrayWriteCharString ".text"
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1
  arrayWrite32LE textLayout.TotalSize ' VirtualSize
  arrayWrite32LE PE_TEXT_RVA ' VirtualAddress
  arrayWrite32LE wTextRawSize ' SizeOfRawData
  arrayWrite32LE PE_FILE_HEADER_OFFSET ' PointerToRawData
  arrayWrite32LE &H00000000 ' PointerToRelocations
  arrayWrite32LE &H00000000 ' PointerToLinenumbers
  arrayWrite16LE &H0000 ' NumberOfRelocations
  arrayWrite16LE &H0000 ' NumberOfLinenumbers
  arrayWrite32LE &HE0000020 ' Characteristics: code, execute, read, write

  '''' Section table - .idata
  arrayWriteCharString ".idata"
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1
  outputFile(outputFileIdx) = 0: outputFileIdx = outputFileIdx + 1
  arrayWrite32LE impTbl.idataRawSize ' VirtualSize
  arrayWrite32LE impTbl.baseRVA ' VirtualAddress
  arrayWrite32LE impTbl.idataRawSize ' SizeOfRawData
  arrayWrite32LE localIdataFileOffset ' PointerToRawData
  arrayWrite32LE &H00000000 ' PointerToRelocations
  arrayWrite32LE &H00000000 ' PointerToLinenumbers
  arrayWrite16LE &H0000 ' NumberOfRelocations
  arrayWrite16LE &H0000 ' NumberOfLinenumbers
  arrayWrite32LE &HC0000040 ' Characteristics: initialized data, read, write

  '''' Pad to file offset (.text raw data start)
  arrayPadUpTo PE_FILE_HEADER_OFFSET, 0

END SUB ' writePEHeader

''''''''''''''''''''''''
SUB return2 (wVal)

  ' Return the global secondary return variable

  returnF2data = wVal

END SUB ' return2

''''''''''''''''''''''''
SUB return3 (wVal)

  ' Return the global tertiary return value

  returnF3data = wVal

END SUB ' return3

''''''''''''''''''''''''
FUNCTION returnedData2

  returnedData2 = returnF2data

END FUNCTION ' returnedData2

''''''''''''''''''''''''
FUNCTION returnedData3

  returnedData3 = returnF3data

END FUNCTION ' returnedData3

''''''''''''''''''''''''
SUB returnExtraPrepare

  ' Call at the top of any function that sends back return 2 or 3 data

  returnF2data = 0
  returnF3data = 0

END SUB ' returnExtraPrepare

''''''''''''''''''''''''
SUB ZLOCATE (wX, wY)

  LOCATE wY + 1, wX + 1

END SUB ' ZLOCATE

''''''''''''''''''''''''
SUB ESCAPE (wVal)

  _DISPLAY

  wStr3$ = " ($" + hexLen$(wVal, 2) + ")"
  wStr2$ = STR$(wVal)
  wStr$ = "PROGRAM ENDED WITH CODE:" + LTRIM$(wStr2$) + wStr3$
  ESCAPETEXT wStr$

END SUB ' ESCAPE

''''''''''''''''''''''''
SUB ESCAPE2 (wVal1, wVal2)

  _DISPLAY

  wStr1$ = STR$(wVal1)
  wStr2$ = STR$(wVal2)

  wStr$ = "PROGRAM ENDED WITH CODES:" + LTRIM$(RTRIM$(wStr1$)) + "," + LTRIM$(RTRIM$(wStr2$)) + "  "

  ESCAPETEXT wStr$

END SUB ' ESCAPE2

''''''''''''''''''''''''
SUB ESCAPETEXT (wStr$)

  ' Do not call redrawAll here, can cause a hang in some cases
  _DISPLAY
  COLOR 15

  IF wStr$ = "" THEN wStr$ = "No text sent"

  PrintTextLineWithBanners wStr$, 15, BOTTOM

  END

END SUB ' ESCAPETEXT

''''''''''''''''''''''''
SUB ESCAPETEXT2 (wStr1$, wStr2$)

  ' Do not call redrawAll here, can cause a hang in some cases
  _DISPLAY
  COLOR 15

  IF wStr1$ = "" THEN wStr1$ = "No text sent"

  fileOutputErrorReport wStr1$, wStr2$

  boxW = SCREENSIZEX - 16
  boxH = 34
  boxX = 8
  boxY = SCREENSIZEY - 128

  drawBorderBox boxX, boxY, boxW, boxH, 1, 0
  drawClearBox boxX + 1, boxY + 1, boxW - 2, boxH - 2, 15

  PrintStr boxX + 8, boxY + 8, wStr1$, 15, 0, 0
  IF wStr2$ <> "" THEN PrintStr boxX + 8, boxY + 18, wStr2$, 15, 0, 0

  END

END SUB ' ESCAPETEXT2

