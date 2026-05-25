' CmpBasic.bas - creates a windows 64 executable file byte by byte with simple BASIC ability

' BASIC commands supported:

' Suffix-less variables are supported, though dynamic strings require a $ suffix
' Variable names have a 64 character limit
' Add GRAPHICS at the beginning for a graphics window (640 x 480 default)
' PSET to draw a single dot to the framebuffer - PSET X, Y, color

' A few of the most common x86 instructions have their own dedicated functions, starting with op

' NOTE: TYPING MECHANICS & THE FRONTEND ENFORCER
' At the core memory-resolution level, the backend ALWAYS uses duck typing
' (Top-Down Implicit Typing / RHS Lookahead) to resolve suffix-less variables.
' However, the frontend (refineCode) acts as a strict "Enforcer". Unless the
' #CLASSIC directive is active, refineCode aggressively polices suffixes and
' throws errors to enforce strict QBasic namespace separation rules.
'
' NOTE: STRING DECLARATIONS (DSTRING vs STRING)
' Strings are an exception to duck typing and are rigorously tracked:
'  - DSTRING : Dynamic string. Automatically forces and strictly enforces a $ suffix.
'  - STRING  : Fixed-length string. Requires a * and a numeric length. Permanently
'              enforces whatever suffix state ($ or no $) was used at declaration.
' Strings implicitly defined will be dynamic
'
' To prevent malformed declarations (e.g., DIM var AS STRING * @#$) from corrupting
' variable tracking on subsequent lines, refineCode uses a "Suspension" state machine.
' It will isolate and ignore the invalid variable until the declaration is fixed.

' NOTE: TIRA (THREE-ADDRESS CODE) NAMESPACE PREFIXES
' The TIRA intermediate representation relies on a strict prefix system to define
' the nature of variables and labels during the compilation phase:
'  ! (Exclamation) : Global compiler/parser state variables (e.g., !GFX_CUR_X)
'  ~ (Tilde)       : Ephemeral, localized TIRA scratchpad variables (e.g., ~T_0)
'                    These are strictly internal and dynamically typed/allocated.
'  & (Ampersand)   : Addresses and compiler-generated Jump Labels (e.g., &MY_LOOP_START)
'                    Established by the parser to signify a memory address or location
'  % (Percent)     : User-defined Labels (e.g., %10, %MY_LABEL).
'                    Automatically applied to isolate custom code target locations

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

CONST ASIS = 0 ' For throwCompilerError
CONST WITHFAILED = 1

CONST USE_DIB_SECTION = 0 ' Use hardware acceleration in output.exe

CONST EDITOR_LINE_MAX = 32768 ' 1-based array tracking is used for code editor lines. This is not the case for the status bar

CONST UI_FLASH_TIME = 0.1

CONST ALIM = 1 ' Allow Implicit

CONST DEFAULT = 0

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
CONST MAX_GFX_PATCHES = MAX_PATCHES
CONST MAX_CTRLS = EDITOR_LINE_MAX \ 16
CONST MAX_CALL_PATCHES = MAX_LABELS
CONST MAX_SUBS = EDITOR_LINE_MAX \ 64
CONST MAX_SYMBOLS = EDITOR_LINE_MAX * 4
CONST MAX_TEXT_CONSTS = EDITOR_LINE_MAX \ 2
CONST MAX_RT_PATCHES = MAX_PATCHES
CONST MAX_UI_SUBS = MAX_SUBS

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
CONST TOK_DISPLAY = 530
CONST TOK_DO = 531
CONST TOK_DOUBLE = 532
CONST TOK_DSTRING = 533 ' Dynamic string
CONST TOK_ELSE = 534
CONST TOK_END = 535
CONST TOK_ERROR = 536
CONST TOK_EXIT = 537
CONST TOK_FONT = 538
CONST TOK_FOR = 539
CONST TOK_FULLSCREEN = 540
CONST TOK_FUNCTION = 541
CONST TOK_GDOUBLE = 542
CONST TOK_GLOBAL = 543
CONST TOK_GOTO = 544
CONST TOK_GRAPHICS = 545
CONST TOK_IF = 546
CONST TOK_INKEY = 547
CONST TOK_INKEYF = 548
CONST TOK_INPUT = 549
CONST TOK_INT = 550
CONST TOK_INTEGER = 551
CONST TOK_INTEGER64 = 552
CONST TOK_KEYDOWN = 553
CONST TOK_LEFT = 554
CONST TOK_LEN = 555
CONST TOK_LET = 556
CONST TOK_LIMIT = 557
CONST TOK_LINE = 558
CONST TOK_LOCATE = 559
CONST TOK_LONG = 560
CONST TOK_LOOP = 561
CONST TOK_LTRIM = 562
CONST TOK_MID = 563
CONST TOK_NEXT = 564
CONST TOK_NOT = 565
CONST TOK_ON = 566
CONST TOK_OR = 567
CONST TOK_PRINT = 568
CONST TOK_PSET = 569
CONST TOK_RESUME = 570
CONST TOK_RETURN = 571
CONST TOK_RIGHT = 572
CONST TOK_RTRIM = 573
CONST TOK_SCREEN = 574
CONST TOK_SELECT = 575
CONST TOK_SHARED = 576
CONST TOK_SINGLE = 577
CONST TOK_STEP = 578
CONST TOK_STR = 579
CONST TOK_STRING = 580
CONST TOK_SUB = 581
CONST TOK_THEN = 582
CONST TOK_TO = 583
CONST TOK_TYPE = 584
CONST TOK_UCASE = 585
CONST TOK_UNSIGNED = 586
CONST TOK_UNTIL = 587
CONST TOK_VAL = 588

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
CONST IAT_RTLMOVEMEMORY = 40
CONST IAT_SELECTOBJECT = 41
CONST IAT_SETBKCOLOR = 42
CONST IAT_SETCONSOLECURSORPOSITION = 43
CONST IAT_SETCONSOLETEXTATTRIBUTE = 44
CONST IAT_SETDIBCOLORTABLE = 45
CONST IAT_SETPIXEL = 46
CONST IAT_SETTEXTCOLOR = 47
CONST IAT_SIN = 48
CONST IAT_SLEEP = 49
CONST IAT_SPRINTF = 50
CONST IAT_STRETCHBLT = 51
CONST IAT_TEXTOUTA = 52

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
CONST TC_ADD = 1
CONST TC_SUB = 2
CONST TC_MUL = 3
CONST TC_DIV = 4
CONST TC_IDIV = 5
CONST TC_AND = 6
CONST TC_OR = 7
CONST TC_POW = 8
CONST TC_CONCAT = 9
CONST TC_ASSIGN = 10
CONST TC_JMP = 11
CONST TC_JMP_USER = 12
CONST TC_READ_MEM = 13
CONST TC_FRAMEBUF_PTR = 14
CONST TC_WRITE_MEM = 15
CONST TC_MEMCPY = 16
CONST TC_MEMSET = 17
CONST TC_JMP_COND = 18
CONST TC_GET_RET = 19
CONST TC_REDRAW = 20
CONST TC_CALL = 21
CONST TC_SWAP_MEM = 22
CONST TC_NEG = 23
CONST TC_NOT = 24
CONST TC_SHL = 25
CONST TC_SHR = 26
CONST TC_LABEL = 27
CONST TC_INTRINSIC = 28
CONST TC_OUTOFRANGE = 29

' Options for later:
'TC_READ_MEM_OFFSET / TC_WRITE_MEM_OFFSET  '
'TC_READ_MEM_DISP / TC_WRITE_MEM_DISP
'TIRA Example: tiraNew TC_WRITE_MEM_OFFSET, "base_ptr, offset, value"

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

CONST TEMP_HEAP_VAR_IDX = -7
CONST PROCESS_HEAP_VAR_IDX = -8

CONST RT_INVALID = 0
CONST RT_KEYDOWN = 1
CONST RT_LINE = 2
CONST RT_PLOT_PIXEL = 3
CONST RT_STR_ASSIGN = 4
CONST RT_VEH_HANDLER = 5

CONST CTRL_IF = 1
CONST CTRL_ELSE = 2
CONST CTRL_FOR = 3
CONST CTRL_DO = 4
CONST CTRL_SELECT = 5

CONST PATCH_VAR = 1
CONST PATCH_IAT = 2
CONST PATCH_GFX = 3
CONST PATCH_GOTO = 4
CONST PATCH_RT = 5
CONST PATCH_CALL = 6

CONST AST_LEAF = 0
CONST AST_ADD = 1
CONST AST_SUB = 2
CONST AST_MUL = 3
CONST AST_DIV = 4
CONST AST_IDIV = 5
CONST AST_AND = 6
CONST AST_OR = 7
CONST AST_CONCAT = 8
CONST AST_POWER = 9

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

CONST OP_TYPE_REG = 5
CONST OP_TYPE_IMM = 6
CONST OP_TYPE_MEM_RIP = 7
CONST OP_TYPE_MEM_RSP = 8
CONST OP_TYPE_MEM_REG = 9
CONST OP_TYPE_MEM_REG_DISP8 = 10
CONST OP_TYPE_ACC = 11
CONST OP_TYPE_REG_ALT = 12
CONST OP_TYPE_MEM_RBP = 13

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
CONST JCC_JS = 8
CONST JCC_JNS = 9
CONST JCC_JP = 10
CONST JCC_JNP = 11
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

TYPE dataTypeAstNode
  OpType AS LONG
  DataType AS LONG
  LeftNode AS LONG
  RightNode AS LONG
  StartIdx AS LONG
  EndIdx AS LONG
END TYPE: DIM SHARED astNodes(8192) AS dataTypeAstNode

TYPE dataTypeCallPatchRecord
  Offset AS LONG
  SubName AS STRING * 64
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

TYPE dataTypeCompilePass4
  SubState AS LONG
  Line AS LONG
  Success AS LONG
END TYPE: COMMON SHARED pass4 AS dataTypeCompilePass4

TYPE dataTypeCtrlRecord
  Type AS LONG
  Patch1 AS LONG
  Patch2 AS LONG
  Patch3 AS LONG ' For EXIT FOR
  ForVarIdx AS LONG
  ForEndVarIdx AS LONG
  ForStepVarIdx AS LONG
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
END TYPE: COMMON SHARED editor AS dataTypeEditor

TYPE dataTypeExpressionState
  DataType AS LONG
  IsTemp AS LONG
END TYPE: COMMON SHARED exprIs AS dataTypeExpressionState

TYPE dataTypeGfxPatchRecord
  Offset AS LONG
  StrIdx AS LONG
END TYPE: DIM SHARED gfxPatches(MAX_GFX_PATCHES) AS dataTypeGfxPatchRecord

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
  IsStr AS LONG
END TYPE: DIM SHARED patches(MAX_PATCHES) AS dataTypePatchRecord

TYPE dataTypeRuntime
  KeyDownOffset AS LONG
  LineOffset AS LONG
  PatchCount AS LONG
  PlotPixelOffset AS LONG
  StrAssignOffset AS LONG
  VehHandlerOffset AS LONG
END TYPE: COMMON SHARED rt AS dataTypeRuntime

TYPE dataTypeRuntimePatchRecord
  Offset AS LONG
  Routine AS LONG
END TYPE: DIM SHARED rtPatches(MAX_RT_PATCHES) AS dataTypeRuntimePatchRecord

TYPE dataTypeStackLayout
  currentStackOffset AS LONG
  consoleFrameSize AS LONG
  slotBytesWritten AS LONG
  slotOverlapped AS LONG
  slotReadBuffer AS LONG
  slotNumptrSpill AS LONG
  slotHandleSave AS LONG
  scratchEndPtr AS LONG
  scratchStartPtr AS LONG
  scratchGfxSpill AS LONG
  numItoaBuffer AS LONG

  TMP_DESC_PTR AS LONG ' Scratchpad for temporary descriptors

  GRAPHICS_MSG_SLOT AS LONG
  GFX_SETUP_FRAME AS LONG
  GFX_WNDPROC_FRAME AS LONG

  SETUP_SLOT_HINSTANCE AS LONG
  SETUP_SLOT_HWND AS LONG
  SETUP_SLOT_BITMAPINFO AS LONG

  WNDPROC_SLOT_HDC AS LONG
  WNDPROC_SLOT_COUNT AS LONG
  WNDPROC_SLOT_BASE AS LONG
  WNDPROC_SLOT_Y AS LONG
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

  WNDPROC_SLOT_TEXTLEN AS LONG
  WNDPROC_SLOT_PAINTSTRUCT AS LONG

  stackIs16Aligned AS LONG ' 1 if properly aligned at a 16 bit boundary, prevents system call crashes
END TYPE: COMMON SHARED stack AS dataTypeStackLayout

TYPE dataTypeSubRecord
  RecordName AS STRING * 64
  Offset AS LONG
  JmpPatchPos AS LONG
  ArgCount AS LONG
  ScopeID AS LONG
  ReturnVarIdx AS LONG
  LocalFrameSize AS LONG
  ExitPatchList AS LONG ' Track EXIT SUB jumps
  AddRspPatchPos AS LONG
  ZeroRcxPatchPos AS LONG
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
  GfxBufBase AS LONG
  HwndBase AS LONG
  MemDCBase AS LONG
  DIBPtrBase AS LONG
  HBitmapBase AS LONG
  FramebufBase AS LONG
  KbdBufBase AS LONG
  KbdHeadBase AS LONG
  KbdTailBase AS LONG
  TotalSize AS LONG
  TotalStrSize AS LONG
  TotalVarSize AS LONG
  TotalDescSize AS LONG
END TYPE: COMMON SHARED textLayout AS dataTypeTextLayout

TYPE dataTypeTira
  TempCounter AS LONG
  LineCount AS LONG
  IsActive AS LONG
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
COMMON SHARED outputFileIdx

COMMON SHARED compileStatusMsg$
COMMON SHARED compileState
COMMON SHARED emitPos

DIM SHARED tiraCmd(MAX_TIRA_LINES) AS LONG

COMMON SHARED tempVarCounter AS LONG ' A deterministic counter reset at the start of every statement used to assign unique
' names to AST and intrinsic temp variables. Prevents dynamic symbol table desyncs across multi-pass compilation
' Decouples temporary AST variables (such as !STRSCR$) from volatile symbolCount to map cleanly across both passes

COMMON SHARED astNodeCount AS LONG ' Abstract syntax tree
COMMON SHARED callPatchCount AS LONG
COMMON SHARED compileClassicMode AS LONG ' Refine process will allow for duck-typing of variables when set
COMMON SHARED compileGraphicsDouble
COMMON SHARED compileHasGraphics
COMMON SHARED compileWindowTitle$
COMMON SHARED ctrlCount AS LONG
COMMON SHARED currentLineNumber AS INTEGER
COMMON SHARED currentSubName$
COMMON SHARED defaultArrayDynamic AS LONG
COMMON SHARED editorSearchQuery$
COMMON SHARED expectedSymType AS LONG
COMMON SHARED funcScrollY
COMMON SHARED gfxPatchCount
COMMON SHARED gotoPatchCount AS LONG
COMMON SHARED iatPatchCount
COMMON SHARED insideSub AS LONG
COMMON SHARED internalErrHandlerSymbolIdx AS LONG
COMMON SHARED internalLastErrRipSymbolIdx AS LONG
COMMON SHARED internalSafeRspSymbolIdx AS LONG
COMMON SHARED intrinsicCount AS LONG
COMMON SHARED isDummyPass AS LONG
COMMON SHARED isFullscreen
COMMON SHARED keyMappingCount AS LONG
COMMON SHARED lastNumericLabel AS LONG
COMMON SHARED lineTokenCount ' Tracks the number of syntax elements currently stored in the lineTokens$ array for the active line
COMMON SHARED patchCount
COMMON SHARED scrollDragActive AS LONG
COMMON SHARED scrollDragOffsetY AS LONG
COMMON SHARED subCount AS LONG
COMMON SHARED symbolCount AS LONG
COMMON SHARED textConstCount AS LONG
COMMON SHARED udtCount AS LONG
COMMON SHARED uiSubCount

COMMON SHARED scopeCounter AS LONG ' Could these be in a data type?
COMMON SHARED currentScopeID AS LONG

COMMON SHARED statusMsgCount
COMMON SHARED currentFrameSize AS LONG

COMMON SHARED internalTempHeapSymbolIdx AS LONG
COMMON SHARED internalTempHeapStartSymbolIdx AS LONG
COMMON SHARED internalProcessHeapSymbolIdx AS LONG

COMMON SHARED lastActionWasTyping AS LONG
COMMON SHARED declareCount AS LONG

COMMON SHARED crlfSlotIdx AS LONG
crlfSlotIdx = -1

COMMON SHARED cornerBoxLastClickTime
cornerBoxLastClickTime = -1

COMMON SHARED editorTextLastClickTime
editorTextLastClickTime = -1

DIM SHARED intermediateCode(1048576) AS _UNSIGNED _BYTE
DIM SHARED symHash(SYMBOL_HASH_MASK) AS LONG

DIM SHARED defIntMap(25) AS LONG ' The 26 letters, C would be stored in the third slot

' The lineTokens$() array is completely overwritten every time the tokenizeLine subroutine processes a new line of code.
DIM SHARED lineTokens$(MAX_TOKENS) ' Temporarily stores the current line's syntax elements and is completely overwritten every time a new line is tokenized

DIM SHARED compileText$(EDITOR_LINE_MAX)
DIM SHARED bmpPal256(256, 4) AS _UNSIGNED _BYTE
DIM SHARED outputPal(256, 4) AS _UNSIGNED _BYTE
DIM SHARED fontData(256, 256) AS _UNSIGNED _BYTE
DIM SHARED outputFile(4194304) AS _UNSIGNED _BYTE
DIM SHARED editorText$(EDITOR_LINE_MAX)


DIM SHARED declareArgType(MAX_SUBS, 16) AS LONG
DIM SHARED declareArgArray(MAX_SUBS, 16) AS LONG

DIM SHARED floatVarData(MAX_SYMBOLS) AS DOUBLE

DIM SHARED impFlatIatRVA(256) AS LONG
DIM SHARED impIatFlatIdx(64) AS LONG

DIM SHARED uiSubName$(MAX_UI_SUBS)
DIM SHARED uiSubLine(MAX_UI_SUBS) AS LONG

' Literal Pool: strVarData$() stores static literal string constants and initial
' spaces for fixed-length string variables. Runtime temporary allocations and
' dynamic string evaluations are managed on the thread-local temporary heap.

DIM SHARED strVarData$(MAX_SYMBOLS)

DIM SHARED statusMsg$(1000)
DIM SHARED subArgVarIdx(MAX_SUBS, 16) AS LONG

DIM SHARED truePatches(MAX_TOKENS) AS LONG
COMMON SHARED truePatchCount AS LONG

DIM SHARED falsePatches(MAX_TOKENS) AS LONG
COMMON SHARED falsePatchCount AS LONG

DIM SHARED undoText$(EDITOR_LINE_MAX)

DIM SHARED tiraCode$(MAX_TIRA_LINES)

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
        statusMsgCount = 0
        editor.StatusScrollY = 0
        editor.StatusSelectedIndex = -1
        FOR ii = 0 TO 999
          statusMsg$(ii) = ""
        NEXT
        compileState = COMP_REFINE
        addStatusMsg "REFINING..."
      END IF
    END IF

    kCtrlF = 0
    IF (_KEYDOWN(100306) OR _KEYDOWN(100305)) AND keyCheck("F") THEN kCtrlF = 1

    IF keyCheck("F3") THEN
      waitKeyRelease "F3"
      IF editorSearchQuery$ <> "" THEN
        findEditorNext
      ELSE
        searchModal
      END IF
    END IF

    IF kCtrlF = 1 THEN
      waitKeyRelease "F"
      searchModal
    END IF

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
SUB addPatch (passType, passOffset, passTargetInt, passIsStr)

  IF isDummyPass = 1 THEN EXIT SUB

  SELECT CASE passType

    CASE PATCH_VAR
      IF patchCount >= MAX_PATCHES THEN
        throwCompilerError "PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      patches(patchCount).Offset = passOffset
      patches(patchCount).VarIdx = passTargetInt
      patches(patchCount).IsStr = passIsStr
      patchCount = patchCount + 1

    CASE PATCH_IAT
      IF iatPatchCount >= MAX_IAT_PATCHES THEN
        throwCompilerError "IAT PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      iatPatches(iatPatchCount).Offset = passOffset
      iatPatches(iatPatchCount).IATIdx = passTargetInt
      iatPatchCount = iatPatchCount + 1

    CASE PATCH_GFX
      IF gfxPatchCount >= MAX_GFX_PATCHES THEN
        throwCompilerError "GFX PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      gfxPatches(gfxPatchCount).Offset = passOffset
      gfxPatches(gfxPatchCount).StrIdx = passTargetInt
      gfxPatchCount = gfxPatchCount + 1

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

  END SELECT ' passType

END SUB ' addPatch

''''''''''''''''''''''''
SUB addPatchStr (passType, passOffset, passTargetStr$)

  IF isDummyPass = 1 THEN EXIT SUB

  SELECT CASE passType

    CASE PATCH_CALL
      IF callPatchCount >= MAX_CALL_PATCHES THEN
        throwCompilerError "CALL PATCH LIMIT", ASIS, 0
        EXIT SUB
      END IF
      callPatches(callPatchCount).Offset = passOffset
      callPatches(callPatchCount).SubName = passTargetStr$
      callPatchCount = callPatchCount + 1

  END SELECT ' passType

END SUB ' addPatchStr

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

  ' Passing -1 triggers the 16-byte alignment logic for the final frame size
  IF wSize = -1 THEN
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

    addStackSpace = currentFrameSize
    EXIT FUNCTION
  END IF

  tempOffset = currentFrameSize
  currentFrameSize = currentFrameSize + wSize
  addStackSpace = tempOffset

END FUNCTION ' addStackSpace

''''''''''''''''''''''''
SUB adjustAllPatchOffsets (offsetDiff, userPatchCnt, userIatPatchCnt, userGfxPatchCnt, userGotoPatchCnt, userCallPatchCnt, userRtPatchCnt, userSubCnt)

  FOR ii = 0 TO userPatchCnt - 1
    patches(ii).Offset = patches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userIatPatchCnt - 1
    iatPatches(ii).Offset = iatPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userGfxPatchCnt - 1
    gfxPatches(ii).Offset = gfxPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO userGotoPatchCnt - 1
    gotoPatches(ii).Offset = gotoPatches(ii).Offset + offsetDiff
  NEXT
  FOR ii = 0 TO symbolCount - 1
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

END SUB ' adjustAllPatchOffsets

''''''''''''''''''''''''
SUB arrayPadNumBytes (wCount, wValue)

  FOR ii = 1 TO wCount
    outputFile(outputFileIdx) = wValue
    outputFileIdx = outputFileIdx + 1
  NEXT

END SUB ' arrayPadNumBytes

''''''''''''''''''''''''
SUB arraypadUpTo (wAddress, wValue)

  IF outputFileIdx < wAddress THEN
    padCount = wAddress - outputFileIdx
    arrayPadNumBytes padCount, wValue
  END IF

END SUB ' arraypadUpTO

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
FUNCTION buildAstArith (startIdx, endIdx)

  ' Expression AST implementation
  ' The expression parser uses an abstract syntax tree to separate syntax analysis from code generation
  ' During the build phase the compiler scans tokens to create a hierarchical tree of nodes representing math and logic operations
  ' Precedence is handled by recursive functions that identify operators from right to left to ensure proper associativity
  ' Each node stores the operation type and an expected data type determined by a lookahead at the variable or literal leaves
  ' Type resolution happens before emission so the compiler can choose between integer and floating point instructions
  ' The emission phase performs a post-order traversal of the tree to generate either x64 machine code or TIRA operations
  ' Intermediate results are managed via the hardware stack or virtual TIRA registers to allow for deeply nested calculations
  ' Complex operations like string functions and array lookups are treated as terminal leaf nodes that route to their respective generator

  DIM pDepth AS LONG
  DIM opIdx AS LONG
  DIM tVal AS LONG
  DIM ii AS LONG
  DIM leftNode AS LONG
  DIM rightNode AS LONG
  DIM nIdx AS LONG
  DIM lType AS LONG
  DIM rType AS LONG
  DIM dt AS LONG

  pDepth = 0
  opIdx = -1
  FOR ii = endIdx TO startIdx STEP -1
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND ii > startIdx THEN
      IF tVal = 256 + ASC("+") OR tVal = 256 + ASC("-") THEN
        opIdx = ii
        EXIT FOR
      END IF
    END IF
  NEXT

  IF opIdx <> -1 THEN
    leftNode = buildAstArith(startIdx, opIdx - 1)
    IF leftNode = -1 THEN
      buildAstArith = -1
      EXIT FUNCTION
    END IF

    rightNode = buildAstTerm(opIdx + 1, endIdx)
    IF rightNode = -1 THEN
      buildAstArith = -1
      EXIT FUNCTION
    END IF

    nIdx = astNodeCount
    astNodeCount = astNodeCount + 1

    tVal = retTokenVal(lineTokens$(opIdx))
    lType = astNodes(leftNode).DataType
    rType = astNodes(rightNode).DataType

    IF lType = TYPE_STRING AND rType = TYPE_STRING THEN
      IF tVal = 256 + ASC("+") THEN
        astNodes(nIdx).OpType = AST_CONCAT
        astNodes(nIdx).DataType = TYPE_STRING
      ELSE
        throwCompilerError "INVALID STRING OP", ASIS, 0
        buildAstArith = -1
        EXIT FUNCTION
      END IF
    ELSE
      IF lType = TYPE_STRING OR rType = TYPE_STRING THEN
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        buildAstArith = -1
        EXIT FUNCTION
      END IF

      IF tVal = 256 + ASC("+") THEN astNodes(nIdx).OpType = AST_ADD
      IF tVal = 256 + ASC("-") THEN astNodes(nIdx).OpType = AST_SUB

      dt = TYPE_LONG
      IF lType = TYPE_SINGLE OR rType = TYPE_SINGLE THEN dt = TYPE_SINGLE
      IF lType = TYPE_DOUBLE OR rType = TYPE_DOUBLE THEN dt = TYPE_DOUBLE
      astNodes(nIdx).DataType = dt
    END IF

    astNodes(nIdx).LeftNode = leftNode
    astNodes(nIdx).RightNode = rightNode
    buildAstArith = nIdx
    EXIT FUNCTION
  END IF

  buildAstArith = buildAstTerm(startIdx, endIdx)

END FUNCTION ' buildAstArith

''''''''''''''''''''''''
FUNCTION buildAstExpression (startIdx, endIdx)

  DIM pDepth AS LONG
  DIM opIdx AS LONG
  DIM tVal AS LONG
  DIM ii AS LONG
  DIM leftNode AS LONG
  DIM rightNode AS LONG
  DIM nIdx AS LONG

  pDepth = 0
  opIdx = -1
  FOR ii = endIdx TO startIdx STEP -1
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND ii > startIdx THEN
      IF tVal = TOK_AND OR tVal = TOK_OR THEN
        opIdx = ii
        EXIT FOR
      END IF
    END IF
  NEXT

  IF opIdx <> -1 THEN
    leftNode = buildAstExpression(startIdx, opIdx - 1)
    IF leftNode = -1 THEN
      buildAstExpression = -1
      EXIT FUNCTION
    END IF

    rightNode = buildAstArith(opIdx + 1, endIdx)
    IF rightNode = -1 THEN
      buildAstExpression = -1
      EXIT FUNCTION
    END IF

    nIdx = astNodeCount
    astNodeCount = astNodeCount + 1
    tVal = retTokenVal(lineTokens$(opIdx))

    IF tVal = TOK_AND THEN astNodes(nIdx).OpType = AST_AND
    IF tVal = TOK_OR THEN astNodes(nIdx).OpType = AST_OR

    astNodes(nIdx).DataType = TYPE_LONG ' Logical AND/OR operates natively on Int bits
    astNodes(nIdx).LeftNode = leftNode
    astNodes(nIdx).RightNode = rightNode

    buildAstExpression = nIdx
    EXIT FUNCTION
  END IF

  buildAstExpression = buildAstArith(startIdx, endIdx)

END FUNCTION ' buildAstExpression

''''''''''''''''''''''''
FUNCTION buildAstFactor (startIdx, endIdx)

  DIM nIdx AS LONG

  nIdx = astNodeCount
  astNodeCount = astNodeCount + 1

  astNodes(nIdx).OpType = AST_LEAF
  astNodes(nIdx).DataType = determineExprType(startIdx, endIdx)
  astNodes(nIdx).StartIdx = startIdx
  astNodes(nIdx).EndIdx = endIdx

  buildAstFactor = nIdx

END FUNCTION ' buildAstFactor

''''''''''''''''''''''''
FUNCTION buildAstPower (startIdx, endIdx)

  DIM pDepth AS LONG
  DIM opIdx AS LONG
  DIM tVal AS LONG
  DIM ii AS LONG
  DIM leftNode AS LONG
  DIM rightNode AS LONG
  DIM nIdx AS LONG
  DIM lType AS LONG
  DIM rType AS LONG

  pDepth = 0
  opIdx = -1
  FOR ii = endIdx TO startIdx STEP -1
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND ii > startIdx THEN
      IF tVal = 256 + ASC("^") THEN
        opIdx = ii
        EXIT FOR
      END IF
    END IF
  NEXT

  IF opIdx <> -1 THEN
    leftNode = buildAstPower(startIdx, opIdx - 1)
    IF leftNode = -1 THEN
      buildAstPower = -1
      EXIT FUNCTION
    END IF

    rightNode = buildAstFactor(opIdx + 1, endIdx)
    IF rightNode = -1 THEN
      buildAstPower = -1
      EXIT FUNCTION
    END IF

    nIdx = astNodeCount
    astNodeCount = astNodeCount + 1

    lType = astNodes(leftNode).DataType
    rType = astNodes(rightNode).DataType

    IF lType = TYPE_STRING OR rType = TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH", ASIS, 0
      buildAstPower = -1
      EXIT FUNCTION
    END IF

    astNodes(nIdx).OpType = AST_POWER
    astNodes(nIdx).DataType = TYPE_DOUBLE ' Power forces DOUBLE evaluation
    astNodes(nIdx).LeftNode = leftNode
    astNodes(nIdx).RightNode = rightNode
    buildAstPower = nIdx
    EXIT FUNCTION
  END IF

  buildAstPower = buildAstFactor(startIdx, endIdx)

END FUNCTION ' buildAstPower

''''''''''''''''''''''''
FUNCTION buildAstTerm (startIdx, endIdx)

  DIM pDepth AS LONG
  DIM opIdx AS LONG
  DIM tVal AS LONG
  DIM ii AS LONG
  DIM leftNode AS LONG
  DIM rightNode AS LONG
  DIM nIdx AS LONG
  DIM lType AS LONG
  DIM rType AS LONG
  DIM dt AS LONG

  pDepth = 0
  opIdx = -1
  FOR ii = endIdx TO startIdx STEP -1
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND ii > startIdx THEN
      IF tVal = 256 + ASC("*") OR tVal = 256 + ASC("/") OR tVal = 256 + ASC("\") THEN
        opIdx = ii
        EXIT FOR
      END IF
    END IF
  NEXT

  IF opIdx <> -1 THEN
    leftNode = buildAstTerm(startIdx, opIdx - 1)
    IF leftNode = -1 THEN
      buildAstTerm = -1
      EXIT FUNCTION
    END IF

    rightNode = buildAstPower(opIdx + 1, endIdx)
    IF rightNode = -1 THEN
      buildAstTerm = -1
      EXIT FUNCTION
    END IF

    nIdx = astNodeCount
    astNodeCount = astNodeCount + 1
    tVal = retTokenVal(lineTokens$(opIdx))

    lType = astNodes(leftNode).DataType
    rType = astNodes(rightNode).DataType

    IF lType = TYPE_STRING OR rType = TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH", ASIS, 0
      buildAstTerm = -1
      EXIT FUNCTION
    END IF

    IF tVal = 256 + ASC("*") THEN astNodes(nIdx).OpType = AST_MUL
    IF tVal = 256 + ASC("/") THEN astNodes(nIdx).OpType = AST_DIV
    IF tVal = 256 + ASC("\") THEN astNodes(nIdx).OpType = AST_IDIV

    IF tVal = 256 + ASC("\") THEN
      astNodes(nIdx).DataType = TYPE_LONG ' IDIV forces integer
    ELSE
      dt = TYPE_LONG
      IF lType = TYPE_SINGLE OR rType = TYPE_SINGLE THEN dt = TYPE_SINGLE
      IF lType = TYPE_DOUBLE OR rType = TYPE_DOUBLE THEN dt = TYPE_DOUBLE
      IF tVal = 256 + ASC("/") AND dt = TYPE_LONG THEN dt = TYPE_SINGLE ' Force float promotion for standard division
      astNodes(nIdx).DataType = dt
    END IF

    astNodes(nIdx).LeftNode = leftNode
    astNodes(nIdx).RightNode = rightNode
    buildAstTerm = nIdx
    EXIT FUNCTION
  END IF

  buildAstTerm = buildAstPower(startIdx, endIdx)

END FUNCTION ' buildAstTerm

''''''''''''''''''''''''
SUB buildImportTable

  impTbl.numDlls = 5

  impDlls(0).DllName = "KERNEL32.dll"
  impDlls(0).FuncCount = 17
  impFuncs(0, 0).FuncName = "GetStdHandle"
  impFuncs(0, 1).FuncName = "WriteFile"
  impFuncs(0, 2).FuncName = "ReadFile"
  impFuncs(0, 3).FuncName = "ExitProcess"
  impFuncs(0, 4).FuncName = "GetModuleHandleA"
  impFuncs(0, 5).FuncName = "SetConsoleMode"
  impFuncs(0, 6).FuncName = "Sleep"
  impFuncs(0, 7).FuncName = "CreateThread"
  impFuncs(0, 8).FuncName = "ExitThread" ' Cleanly terminates the calling thread. The proper way to shut down an individual thread without terminating the parent process
  impFuncs(0, 9).FuncName = "SetConsoleCursorPosition"
  impFuncs(0, 10).FuncName = "SetConsoleTextAttribute"
  impFuncs(0, 11).FuncName = "GetProcessHeap"
  impFuncs(0, 12).FuncName = "HeapAlloc"
  impFuncs(0, 13).FuncName = "HeapFree"
  impFuncs(0, 14).FuncName = "RtlMoveMemory"
  impFuncs(0, 15).FuncName = "AddVectoredExceptionHandler"
  impFuncs(0, 16).FuncName = "Beep"

  impDlls(1).DllName = "USER32.dll"
  impDlls(1).FuncCount = 14
  impFuncs(1, 0).FuncName = "DefWindowProcA"
  impFuncs(1, 1).FuncName = "RegisterClassExA"
  impFuncs(1, 2).FuncName = "CreateWindowExA"
  impFuncs(1, 3).FuncName = "ShowWindow"
  impFuncs(1, 4).FuncName = "PeekMessageA"
  impFuncs(1, 5).FuncName = "TranslateMessage"
  impFuncs(1, 6).FuncName = "DispatchMessageA"
  impFuncs(1, 7).FuncName = "PostQuitMessage"
  impFuncs(1, 8).FuncName = "BeginPaint"
  impFuncs(1, 9).FuncName = "EndPaint"
  impFuncs(1, 10).FuncName = "LoadCursorA"
  impFuncs(1, 11).FuncName = "InvalidateRect"
  impFuncs(1, 12).FuncName = "GetAsyncKeyState"
  impFuncs(1, 13).FuncName = "AdjustWindowRectEx"

  impDlls(2).DllName = "GDI32.dll"
  impDlls(2).FuncCount = 15
  impFuncs(2, 0).FuncName = "TextOutA"
  impFuncs(2, 1).FuncName = "GetStockObject"
  impFuncs(2, 2).FuncName = "SelectObject"
  impFuncs(2, 3).FuncName = "SetTextColor"
  impFuncs(2, 4).FuncName = "SetBkColor"
  impFuncs(2, 5).FuncName = "SetPixel"
  impFuncs(2, 6).FuncName = "CreateFontA"
  impFuncs(2, 7).FuncName = "StretchBlt"
  impFuncs(2, 8).FuncName = "CreateCompatibleDC"
  impFuncs(2, 9).FuncName = "CreateCompatibleBitmap"
  impFuncs(2, 10).FuncName = "DeleteDC"
  impFuncs(2, 11).FuncName = "DeleteObject"
  impFuncs(2, 12).FuncName = "CreateDIBSection" ' Creates a Device-Independent Bitmap (DIB) that the program can write to directly. Allocates memory for the bitmap's pixels and hands off a direct memory pointer to those pixels
  impFuncs(2, 13).FuncName = "BitBlt"
  impFuncs(2, 14).FuncName = "SetDIBColorTable"

  impDlls(3).DllName = "DWMAPI.dll"
  impDlls(3).FuncCount = 1
  impFuncs(3, 0).FuncName = "DwmSetWindowAttribute"

  impDlls(4).DllName = "msvcrt.dll"
  impDlls(4).FuncCount = 4
  impFuncs(4, 0).FuncName = "sprintf"
  impFuncs(4, 1).FuncName = "atof"
  impFuncs(4, 2).FuncName = "atan"
  impFuncs(4, 3).FuncName = "pow"

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
      iatConst = retIatConstByName(fName$)
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
FUNCTION cClamp (wVal, wMin, wMax) ' Custom clamp

  ' Returns the value of wVal, but constrained within wMin and wMax
  ' This can be used to prevent array access errors
  tempReturn = wVal
  IF tempReturn < wMin THEN tempReturn = wMin
  IF tempReturn > wMax THEN tempReturn = wMax
  cClamp = tempReturn

END FUNCTION ' cClamp

''''''''''''''''''''''''
SUB checkEmergencyClose

  mouseReadInput
  IF mouse.Released1 THEN
    IF mouseWithinBoxBounds(SCREENSIZEX - 15, 0, 15, 13) AND mouseDownWithinBoxBounds(SCREENSIZEX - 15, 0, 15, 13) THEN
      compileStatusMsg$ = "ERROR: ABORTED BY USER"
      editor.TopMenuFocus = 4
      editor.Focus = 0
      editor.MenuClicked = 1
    END IF
  END IF

END SUB ' checkEmergencyClose

''''''''''''''''''''''''
FUNCTION compile

  currentLineNumber = 1
  tempSuccess = 1
  compileStatusMsg$ = ""
  emitPos = 0
  symbolCount = 0
  scopeCounter = 0
  currentScopeID = 0 ' Start in the global scope
  lineTokenCount = 0
  patchCount = 0
  iatPatchCount = 0
  gfxPatchCount = 0
  compileHasGraphics = 0
  compileGraphicsDouble = 0
  compileClassicMode = 0
  expectedSymType = TYPE_ANY
  compileWindowTitle$ = "Default"
  crlfSlotIdx = -1
  ctrlCount = 0
  gotoPatchCount = 0
  lastNumericLabel = -1
  tempVarCounter = 0

  t.LineCount = 0
  t.TempCounter = 0
  t.IsActive = 0

  exprIs.DataType = TYPE_LONG
  exprIs.IsTemp = 0

  rt.PatchCount = 0
  rt.StrAssignOffset = 0
  rt.LineOffset = 0
  rt.PlotPixelOffset = 0
  rt.VehHandlerOffset = 0
  rt.KeyDownOffset = 0

  FOR ii = 0 TO 25
    defIntMap(ii) = 0
  NEXT

  subCount = 0
  callPatchCount = 0
  insideSub = 0
  currentSubName$ = ""
  declareCount = 0

  initSymbolHash
  initStackLayout

  ff = updateStackAlignment

  gfxConfig.SizeX = 640 ' Defaults if not specified
  gfxConfig.SizeY = 480

  ' Define internal heap pointers early so they get VarBase slots
  internalTempHeapSymbolIdx = resolveSymbol("!TEMP_HEAP_PTR")
  internalTempHeapStartSymbolIdx = resolveSymbol("!TEMP_HEAP_START")
  internalProcessHeapSymbolIdx = resolveSymbol("!PROCESS_HEAP_PTR")
  internalErrHandlerSymbolIdx = resolveSymbol("!ERR_HANDLER_PTR")
  internalSafeRspSymbolIdx = resolveSymbol("!SAFE_RSP")
  internalLastErrRipSymbolIdx = resolveSymbol("!LAST_ERR_RIP")

  ff = resolveSymbol("!LAST_FG_COLOR")
  ff = resolveSymbol("!LAST_BG_COLOR")
  ff = resolveSymbol("!COLOR_INIT")

  ff = resolveSymbol("!RT_ARG1")
  ff = resolveSymbol("!RT_ARG2")
  ff = resolveSymbol("!RT_ARG3")
  ff = resolveSymbol("!RT_PLOT_OFFSET")
  ff = resolveSymbol("!RT_PLOT_FBBASE")
  ff = resolveSymbol("!RT_PLOT_TARGET")

  ff = resolveSymbol("!RT_X1")
  ff = resolveSymbol("!RT_Y1")
  ff = resolveSymbol("!RT_X2")
  ff = resolveSymbol("!RT_Y2")
  ff = resolveSymbol("!RT_COLOR")
  ff = resolveSymbol("!RT_BOX")
  ff = resolveSymbol("!RT_STYLE")
  ff = resolveSymbol("!RT_DX")
  ff = resolveSymbol("!RT_DY")
  ff = resolveSymbol("!RT_SX")
  ff = resolveSymbol("!RT_SY")
  ff = resolveSymbol("!RT_ERR")
  ff = resolveSymbol("!RT_E2")
  ff = resolveSymbol("!RT_TMPX")
  ff = resolveSymbol("!RT_TMPY")
  ff = resolveSymbol("!RT_STYLE_BIT")
  ff = resolveSymbol("!RT_STYLE_HIGH")
  ff = resolveSymbol("!RT_STYLE_LOW")

  vIdxExit = resolveSymbol("!EXIT_CODE")
  IF vIdxExit <> -1 THEN
    symbols(vIdxExit).DataType = TYPE_LONG
  END IF

  ' Pre-declare singleton literal strings to guarantee safe isolation in the String Pool
  fmtIdx = resolveSymbol("!FMT_G$")
  IF fmtIdx <> -1 THEN strVarData$(fmtIdx) = "%g"

  pauseStrIdx = resolveSymbol("!PAUSE_STR$")
  IF pauseStrIdx <> -1 THEN strVarData$(pauseStrIdx) = "Press any key to continue..."

  crlfIdx = resolveSymbol("!CRLF$")
  IF crlfIdx <> -1 THEN strVarData$(crlfIdx) = CHR$(13) + CHR$(10)

  clsScrIdx = resolveSymbol("!CLSSCR$")
  IF clsScrIdx <> -1 THEN strVarData$(clsScrIdx) = STRING$(120, 32) + CHR$(13) + CHR$(10)

  emptyDescIdx = resolveSymbol("!EMPTY_DESC$")
  IF emptyDescIdx <> -1 THEN strVarData$(emptyDescIdx) = ""

  FOR iy = 1 TO EDITOR_LINE_MAX
    compileText$(iy) = ""
  NEXT

  compileText$(0) = "LINE 0: YOU SHOULD NEVER SEE THIS"

  compilePass1LexiConsts

  gfxPalIdx = resolveSymbol("!GFX_PALETTE$")
  IF gfxPalIdx <> -1 THEN
    palStr$ = ""
    FOR ii = 0 TO 255
      palStr$ = palStr$ + CHR$(outputPal(ii, palRED))
      palStr$ = palStr$ + CHR$(outputPal(ii, palGREEN))
      palStr$ = palStr$ + CHR$(outputPal(ii, palBLUE))
      palStr$ = palStr$ + CHR$(0)
    NEXT
    strVarData$(gfxPalIdx) = palStr$
  END IF

  gfxFgIdx = resolveSymbol("!GFX_FG_RGB")

  ' Pre-declare internal tracking variables in global scope
  ff = resolveSymbol("!GFX_CUR_X")
  ff = resolveSymbol("!GFX_CUR_Y")
  ff = resolveSymbol("!GFX_BUF_COUNT")

  compilePass2Scan

  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    compile = 0
    EXIT FUNCTION
  END IF

  compilePass3Symbols

  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    compile = 0
    EXIT FUNCTION
  END IF

  compile = 1

END FUNCTION ' compile

''''''''''''''''''''''''
SUB compilePass1LexiConsts

  ' Pass 1: Performs a double sweep to register and evaluate all CONST declarations
  ' Replaces all constant names with literal values throughout the source file
  ' Fully expanded lines are written to the compileText$ array for pass 2

  DIM isLabel AS LONG
  DIM stripLen AS LONG
  DIM eqPos AS LONG
  DIM inQuotes AS LONG
  DIM valLen AS LONG
  DIM isIdentStart AS LONG
  DIM matched AS LONG
  DIM inQ AS LONG
  DIM exLen AS LONG
  DIM lineLen AS LONG
  DIM preventExpansion AS LONG
  DIM prevIx AS LONG
  DIM prevCh AS STRING * 1
  DIM inTypeBlock AS LONG
  DIM firstWordFound AS LONG

  textConstCount = 0

  ' This loop exists to perform the first sweep over every line of code in the editor
  ' The goal of this specific loop is strictly to find CONST declarations and harvest their values
  FOR iy = 1 TO editor.LastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    currentLineNumber = iy
    curLine$ = editorText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    isLabel = 0
    stripLen = 0

    firstChar$ = LEFT$(tempLine$, 1)
    IF firstChar$ >= "0" AND firstChar$ <= "9" THEN
      FOR i_check = 1 TO LEN(tempLine$)
        chCheck$ = MID$(tempLine$, i_check, 1)
        IF chCheck$ >= "0" AND chCheck$ <= "9" THEN
          stripLen = stripLen + 1
        ELSE
          EXIT FOR
        END IF
      NEXT
      isLabel = 1
      IF stripLen < LEN(tempLine$) THEN
        IF MID$(tempLine$, stripLen + 1, 1) = ":" THEN
          stripLen = stripLen + 1
        END IF
      END IF
    END IF

    rawNoLabel$ = tempLine$
    IF isLabel = 1 THEN
      rawNoLabel$ = LTRIM$(MID$(tempLine$, stripLen + 1))
    END IF

    ' Check the first six characters of the cleaned line to see if it says CONST
    IF UCASE$(LEFT$(rawNoLabel$, 6)) = "CONST " THEN
      remLine$ = LTRIM$(MID$(rawNoLabel$, 7))
      eqPos = INSTR(remLine$, "=")
      IF eqPos > 0 THEN
        cName$ = UCASE$(LTRIM$(RTRIM$(LEFT$(remLine$, eqPos - 1))))
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
              u$ = UCASE$(ch$)
              IF (u$ >= "A" AND u$ <= "Z") OR u$ = "_" THEN isIdentStart = 1

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
                  IF chCheckSuffix$ = "$" OR chCheckSuffix$ = "#" OR chCheckSuffix$ = "!" THEN
                    ident$ = ident$ + chCheckSuffix$
                    ix = ix + 1
                  END IF
                END IF

                matched = -1
                searchIdent$ = UCASE$(ident$)

                ' Only check dictionary if we are safe from structural collisions
                IF preventExpansion = 0 THEN
                  FOR iConst = 0 TO textConstCount - 1
                    IF UCASE$(textConsts(iConst).Name) = searchIdent$ THEN
                      matched = iConst
                      EXIT FOR
                    END IF
                  NEXT
                END IF

                IF matched <> -1 THEN
                  expandedVal$ = expandedVal$ + textConsts(matched).Value
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
          IF inQ = 0 AND cv$ = "'" THEN EXIT FOR
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

    isLabel = 0
    stripLen = 0

    firstChar$ = LEFT$(tempLine$, 1)
    IF firstChar$ >= "0" AND firstChar$ <= "9" THEN
      FOR i_check = 1 TO LEN(tempLine$)
        chCheck$ = MID$(tempLine$, i_check, 1)
        IF chCheck$ >= "0" AND chCheck$ <= "9" THEN
          stripLen = stripLen + 1
        ELSE
          EXIT FOR
        END IF
      NEXT
      isLabel = 1
      IF stripLen < LEN(tempLine$) THEN
        IF MID$(tempLine$, stripLen + 1, 1) = ":" THEN
          stripLen = stripLen + 1
        END IF
      END IF
    END IF

    rawNoLabel$ = tempLine$
    IF isLabel = 1 THEN
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
            expandedLine$ = expandedLine$ + MID$(curLine$, ix)
            EXIT DO
          ELSE
            isIdentStart = 0
            u$ = UCASE$(ch$)
            IF (u$ >= "A" AND u$ <= "Z") OR u$ = "_" THEN isIdentStart = 1

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
                IF chCheckSuffix$ = "$" OR chCheckSuffix$ = "#" OR chCheckSuffix$ = "!" THEN
                  ident$ = ident$ + chCheckSuffix$
                  ix = ix + 1
                END IF
              END IF

              matched = -1
              searchIdent$ = UCASE$(ident$)

              ' Check the harvested constants array to see if the word we just isolated is a known constant
              IF preventExpansion = 0 THEN
                FOR iConst = 0 TO textConstCount - 1
                  IF UCASE$(textConsts(iConst).Name) = searchIdent$ THEN
                    matched = iConst
                    EXIT FOR
                  END IF
                NEXT
              END IF

              ' If a match is found, append the literal value into the line buffer instead of the name
              IF matched <> -1 THEN
                expandedLine$ = expandedLine$ + textConsts(matched).Value
              ELSE
                expandedLine$ = expandedLine$ + ident$
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

  currentLineNumber = 1

END SUB ' compilePass1LexiConsts

''''''''''''''''''''''''
SUB compilePass2Scan

  ' Pass 2: Scans for compiler directives and handles label stripping
  ' Validates that directives like #GRAPHICS or #DEFINT appear before any code
  ' Logs warnings for unsupported legacy QBasic screen and display commands

  DIM firstCodeLineFound AS LONG
  DIM isLabel AS LONG
  DIM stripLen AS LONG
  DIM tempStrip AS LONG
  DIM tVal AS LONG
  DIM tokIdx AS LONG
  DIM char1 AS LONG
  DIM char2 AS LONG

  firstCodeLineFound = 0
  defaultArrayDynamic = 0

  FOR iy = 1 TO editor.LastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB


    currentLineNumber = iy
    curLine$ = compileText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    IF LEN(tempLine$) > 0 THEN
      isLabel = 0
      labelStr$ = ""
      stripLen = 0

      firstChar$ = LEFT$(tempLine$, 1)
      IF firstChar$ >= "0" AND firstChar$ <= "9" THEN
        FOR i_check = 1 TO LEN(tempLine$)
          chCheck$ = MID$(tempLine$, i_check, 1)
          IF chCheck$ >= "0" AND chCheck$ <= "9" THEN
            labelStr$ = labelStr$ + chCheck$
            stripLen = stripLen + 1
          ELSE
            EXIT FOR
          END IF
        NEXT
        isLabel = 1
        IF stripLen < LEN(tempLine$) THEN
          IF MID$(tempLine$, stripLen + 1, 1) = ":" THEN
            stripLen = stripLen + 1
          END IF
        END IF
      ELSE
        uFirst$ = UCASE$(firstChar$)
        IF (uFirst$ >= "A" AND uFirst$ <= "Z") THEN
          tempStrip = 0
          tempLabel$ = ""
          FOR i_check = 1 TO LEN(tempLine$)
            chCheck$ = UCASE$(MID$(tempLine$, i_check, 1))
            IF (chCheck$ >= "A" AND chCheck$ <= "Z") OR (chCheck$ >= "0" AND chCheck$ <= "9") OR chCheck$ = "_" THEN
              tempLabel$ = tempLabel$ + chCheck$
              tempStrip = tempStrip + 1
            ELSE
              EXIT FOR
            END IF
          NEXT
          IF tempStrip < LEN(tempLine$) THEN
            IF MID$(tempLine$, tempStrip + 1, 1) = ":" THEN
              isLabel = 1
              labelStr$ = tempLabel$
              stripLen = tempStrip + 1
            END IF
          END IF
        END IF
      END IF

      IF isLabel = 1 THEN
        tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
      END IF

      IF LEN(tempLine$) > 0 THEN
        tokenizeLine tempLine$
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

        IF lineTokenCount > 0 THEN
          FOR iTok = 0 TO lineTokenCount - 1
            tVal = retTokenVal(lineTokens$(iTok))
            IF tVal = TOK_SCREEN OR tVal = TOK_FULLSCREEN OR tVal = TOK_FONT OR tVal = TOK_LIMIT OR tVal = TOK_DISPLAY THEN
              warnStr$ = "UNKNOWN"
              IF voc(tVal).text <> "" THEN
                warnStr$ = voc(tVal).text
              END IF
              addStatusMsg "WARNING line " + retLineNumberStr$ + ": " + warnStr$ + " UNSUPPORTED, LINE IGNORED"
            END IF
          NEXT

          firstTok$ = lineTokens$(0)
          tVal = retTokenVal(firstTok$)

          IF tVal = TOK_GRAPHICS OR tVal = TOK_GDOUBLE OR tVal = TOK_DEFINT OR tVal = TOK_CLASSIC THEN
            IF firstCodeLineFound = 1 THEN
              throwCompilerError "DIRECTIVES MUST COME BEFORE CODE", ASIS, 0
              EXIT SUB
            END IF
            IF tVal = TOK_CLASSIC THEN compileClassicMode = 1
            IF tVal = TOK_GRAPHICS THEN compileHasGraphics = 1
            IF tVal = TOK_GDOUBLE THEN compileGraphicsDouble = 1
            IF tVal = TOK_DEFINT THEN
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
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("-") THEN
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
                FOR c = char1 TO char2
                  defIntMap(c - 65) = 1
                NEXT
                IF tokIdx < lineTokenCount THEN
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
                    tokIdx = tokIdx + 1
                  ELSE
                    throwCompilerError "EXPECTED COMMA", ASIS, 0
                    EXIT SUB
                  END IF
                END IF
              LOOP
            END IF
          ELSE
            firstCodeLineFound = 1
          END IF
        END IF
      END IF
    END IF
  NEXT

  currentLineNumber = 1

END SUB ' compilePass2Scan

''''''''''''''''''''''''
SUB compilePass3Symbols

  ' Pass 3: Discovers and registers all symbols (Labels, Subs, Functions, UDTs, Declares)
  ' Validates matching signatures between DECLARE statements and actual subroutine definitions
  ' Builds the scope mapping and structure offsets for complex data types

  DIM inTypeBlock AS LONG
  DIM currentUdtIdx AS LONG
  DIM isLabel AS LONG
  DIM stripLen AS LONG
  DIM tempStrip AS LONG
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
  DIM tType AS LONG
  DIM fieldSize AS LONG
  DIM fieldType AS LONG
  DIM matchedUdt AS LONG
  DIM fIdx AS LONG
  DIM nameIdx AS LONG
  DIM vIdxArg AS LONG
  DIM subIdx AS LONG
  DIM retVarIdx AS LONG
  DIM argVarIdx AS LONG
  DIM tempUdtIndex AS LONG

  inTypeBlock = 0
  currentUdtIdx = -1
  udtCount = 0 ' Initialize the global UDT counter
  defaultArrayDynamic = 0

  FOR iy = 1 TO editor.LastLine
    checkEmergencyClose
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    currentLineNumber = iy
    curLine$ = compileText$(iy)
    tempLine$ = LTRIM$(RTRIM$(curLine$))

    IF LEN(tempLine$) > 0 THEN
      isLabel = 0
      labelStr$ = ""
      stripLen = 0

      firstChar$ = LEFT$(tempLine$, 1)
      IF firstChar$ >= "0" AND firstChar$ <= "9" THEN
        FOR i_check = 1 TO LEN(tempLine$)
          chCheck$ = MID$(tempLine$, i_check, 1)
          IF chCheck$ >= "0" AND chCheck$ <= "9" THEN
            labelStr$ = labelStr$ + chCheck$
            stripLen = stripLen + 1
          ELSE
            EXIT FOR
          END IF
        NEXT
        isLabel = 1
        IF stripLen < LEN(tempLine$) THEN
          IF MID$(tempLine$, stripLen + 1, 1) = ":" THEN
            stripLen = stripLen + 1
          END IF
        END IF
      ELSE
        uFirst$ = UCASE$(firstChar$)
        IF (uFirst$ >= "A" AND uFirst$ <= "Z") THEN
          tempStrip = 0
          tempLabel$ = ""
          FOR i_check = 1 TO LEN(tempLine$)
            chCheck$ = UCASE$(MID$(tempLine$, i_check, 1))
            IF (chCheck$ >= "A" AND chCheck$ <= "Z") OR (chCheck$ >= "0" AND chCheck$ <= "9") OR chCheck$ = "_" THEN
              tempLabel$ = tempLabel$ + chCheck$
              tempStrip = tempStrip + 1
            ELSE
              EXIT FOR
            END IF
          NEXT
          IF tempStrip < LEN(tempLine$) THEN
            IF MID$(tempLine$, tempStrip + 1, 1) = ":" THEN
              isLabel = 1
              labelStr$ = tempLabel$
              stripLen = tempStrip + 1
            END IF
          END IF
        END IF
      END IF

      IF isLabel = 1 THEN
        labelName$ = UCASE$(labelStr$)

        isNum = 1
        FOR i_check = 1 TO LEN(labelName$)
          chCheck$ = MID$(labelName$, i_check, 1)
          IF chCheck$ < "0" OR chCheck$ > "9" THEN isNum = 0: EXIT FOR
        NEXT

        IF isNum = 1 THEN
          IF currentScopeID > 0 THEN
            throwCompilerError "NUMERIC LABELS NOT ALLOWED IN SUB OR FUNCTION", ASIS, 0
            EXIT SUB
          END IF

          numVal = VAL(labelName$)
          IF numVal <= lastNumericLabel THEN
            throwCompilerError "NUMERIC LABEL " + LTRIM$(RTRIM$(STR$(numVal))) + " FOUND AFTER " + LTRIM$(RTRIM$(STR$(lastNumericLabel))), ASIS, 0
            EXIT SUB
          END IF
          lastNumericLabel = numVal
        END IF

        ' Unconditionally prefix ALL user labels with % to isolate them from variable namespaces
        labelName$ = "%" + labelName$

        vIdx = resolveSymbol(labelName$)
        IF vIdx = -1 THEN EXIT SUB

        IF symbols(vIdx).alreadyParsed = 1 THEN
          throwCompilerError "DUPLICATE LABEL " + labelStr$, ASIS, 0
          EXIT SUB
        END IF

        symbols(vIdx).DataType = TYPE_LABEL
        symbols(vIdx).Offset = -1
        symbols(vIdx).IsExplicit = 1
        symbols(vIdx).alreadyParsed = 1

        tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
      END IF

      IF LEN(tempLine$) > 0 THEN
        tokenizeLine tempLine$

        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

        IF lineTokenCount > 0 THEN
          firstTok$ = lineTokens$(0)
          tVal = retTokenVal(firstTok$)
          isUdtLine = 0

          IF tVal = TOK_DECLARE THEN
            isUdtLine = 1 ' Mark as handled so it ignores SUB/FUNCTION registration
            IF lineTokenCount >= 3 THEN
              tVal2 = retTokenVal(lineTokens$(1))
              IF tVal2 = TOK_SUB OR tVal2 = TOK_FUNCTION THEN
                dName$ = UCASE$(lineTokens$(2))
                dRetType = TYPE_UNDEFINED ' Default inert type for SUB

                IF tVal2 = TOK_FUNCTION THEN
                  declares(declareCount).IsFunction = 1
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
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
                    tokIdx = tokIdx + 1
                    DO WHILE tokIdx < lineTokenCount
                      argTok$ = lineTokens$(tokIdx)
                      IF retTokenVal(argTok$) = 256 + ASC(")") THEN EXIT DO
                      IF retTokenVal(argTok$) = 0 THEN
                        aName$ = UCASE$(argTok$)

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
                          IF retTokenVal(lineTokens$(tokIdx + 1)) = 256 + ASC("(") THEN
                            IF tokIdx + 2 < lineTokenCount THEN
                              IF retTokenVal(lineTokens$(tokIdx + 2)) = 256 + ASC(")") THEN
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
                          IF retTokenVal(lineTokens$(tokIdx + 1)) = TOK_AS THEN
                            tokIdx = tokIdx + 2
                            IF tokIdx < lineTokenCount THEN
                              tType = retTokenVal(lineTokens$(tokIdx))

                              SELECT CASE tType

                                CASE TOK_ANY
                                  aType = TYPE_ANY
                                CASE TOK_INTEGER
                                  aType = TYPE_INTEGER
                                CASE TOK_LONG
                                  aType = TYPE_LONG
                                CASE TOK_SINGLE
                                  aType = TYPE_SINGLE
                                CASE TOK_DOUBLE
                                  aType = TYPE_DOUBLE
                                CASE TOK_DSTRING
                                  aType = TYPE_STRING
                                CASE TOK_STRING
                                  aType = TYPE_STRING
                                  IF tokIdx + 1 < lineTokenCount THEN
                                    IF retTokenVal(lineTokens$(tokIdx + 1)) = 256 + ASC("*") THEN
                                      tokIdx = tokIdx + 2
                                    ELSE
                                      throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                                      EXIT SUB
                                    END IF
                                  ELSE
                                    throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                                    EXIT SUB
                                  END IF
                                CASE 0
                                  aType = TYPE_UDT
                                CASE ELSE
                                  throwCompilerError "UNSUPPORTED TYPE IN DECLARE", ASIS, 0
                                  EXIT SUB

                              END SELECT ' tType

                            ELSE
                              throwCompilerError "EXPECTED TYPE AFTER AS", ASIS, 0
                              EXIT SUB
                            END IF
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
                        IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
                          tokIdx = tokIdx + 1
                        ELSE
                          IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(")") THEN
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
                compileText$(iy) = "" ' Erase line so Pass 4 ignores it

              ELSE
                throwCompilerError "EXPECTED SUB OR FUNCTION AFTER DECLARE", ASIS, 0
                EXIT SUB
              END IF
            ELSE
              throwCompilerError "MALFORMED DECLARE", ASIS, 0
              EXIT SUB
            END IF
          END IF

          IF inTypeBlock = 1 THEN
            isUdtLine = 1
            IF tVal = TOK_END THEN
              IF lineTokenCount >= 2 THEN
                IF retTokenVal(lineTokens$(1)) = TOK_TYPE THEN
                  inTypeBlock = 0
                  compileText$(iy) = "" ' Erase line so Pass 4 ignores it
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
                IF retTokenVal(lineTokens$(1)) = TOK_AS THEN
                  tokIdx = 2
                  fieldSize = 0
                  fieldType = 0
                  tempUdtIndex = 0

                  IF retTokenVal(lineTokens$(tokIdx)) = TOK_UNSIGNED THEN
                    tokIdx = tokIdx + 1
                    IF tokIdx < lineTokenCount THEN
                      tType = retTokenVal(lineTokens$(tokIdx))

                      SELECT CASE tType

                        CASE TOK_BYTE
                          fieldType = TYPE_UBYTE: fieldSize = 1
                        CASE TOK_INTEGER
                          fieldType = TYPE_UINTEGER: fieldSize = 2
                        CASE TOK_LONG
                          fieldType = TYPE_ULONG: fieldSize = 4
                        CASE TOK_INTEGER64
                          fieldType = TYPE_UINT64: fieldSize = 8
                        CASE ELSE
                          throwCompilerError "EXPECTED _BYTE, INTEGER, LONG, OR _INTEGER64 BUT GOT " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                          EXIT SUB

                      END SELECT ' tType

                    ELSE
                      throwCompilerError "EXPECTED TYPE AFTER _UNSIGNED", ASIS, 0
                      EXIT SUB
                    END IF
                  ELSE
                    tType = retTokenVal(lineTokens$(tokIdx))

                    SELECT CASE tType

                      CASE TOK_LONG
                        fieldType = TYPE_LONG: fieldSize = 4
                      CASE TOK_INTEGER
                        fieldType = TYPE_INTEGER: fieldSize = 2
                      CASE TOK_BYTE
                        fieldType = TYPE_BYTE: fieldSize = 1
                      CASE TOK_INTEGER64
                        fieldType = TYPE_INTEGER64: fieldSize = 8
                      CASE TOK_SINGLE
                        fieldType = TYPE_SINGLE: fieldSize = 4
                      CASE TOK_DOUBLE
                        fieldType = TYPE_DOUBLE: fieldSize = 8
                      CASE TOK_DSTRING
                        fieldType = TYPE_STRING
                        fieldSize = 8
                        tempUdtIndex = 1
                      CASE TOK_STRING
                        fieldType = TYPE_STRING
                        IF tokIdx + 1 < lineTokenCount THEN
                          IF retTokenVal(lineTokens$(tokIdx + 1)) = 256 + ASC("*") THEN
                            tokIdx = tokIdx + 2
                            IF tokIdx < lineTokenCount THEN
                              sizeTok$ = lineTokens$(tokIdx)
                              isNum = 1
                              FOR i_check = 1 TO LEN(sizeTok$)
                                chCheck$ = MID$(sizeTok$, i_check, 1)
                                IF chCheck$ < "0" OR chCheck$ > "9" THEN isNum = 0: EXIT FOR
                              NEXT
                              IF isNum = 0 THEN
                                throwCompilerError "STRING LENGTH MUST BE CONSTANT", ASIS, 0
                                EXIT SUB
                              END IF
                              fieldSize = VAL(sizeTok$)
                            ELSE
                              throwCompilerError "EXPECTED STRING LENGTH", ASIS, 0
                              EXIT SUB
                            END IF
                          ELSE
                            throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                            EXIT SUB
                          END IF
                        ELSE
                          throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                          EXIT SUB
                        END IF
                      CASE 0 ' UDT Identifier
                        uTok$ = UCASE$(lineTokens$(tokIdx))
                        matchedUdt = -1
                        FOR iUdt = 0 TO udtCount - 1
                          IF RTRIM$(udts(iUdt).RecordName) = uTok$ THEN
                            matchedUdt = iUdt
                            EXIT FOR
                          END IF
                        NEXT
                        IF matchedUdt <> -1 THEN
                          fieldType = TYPE_UDT
                          fieldSize = udts(matchedUdt).TotalSize
                          tempUdtIndex = matchedUdt
                        ELSE
                          throwCompilerError "UNSUPPORTED TYPE OR UNKNOWN UDT " + CHR$(34) + lineTokens$(tokIdx) + CHR$(34), ASIS, 0
                          EXIT SUB
                        END IF
                      CASE ELSE
                        throwCompilerError "UNSUPPORTED TYPE " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                        EXIT SUB

                    END SELECT ' tType

                  END IF

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

                  udts(currentUdtIdx).TotalSize = udts(currentUdtIdx).TotalSize + fieldSize
                  udts(currentUdtIdx).FieldCount = udts(currentUdtIdx).FieldCount + 1

                  compileText$(iy) = "" ' Erase line so Pass 4 ignores it
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

                compileText$(iy) = "" ' Erase line so Pass 4 ignores it
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
                  vIdx = resolveSymbol(subName$)
                  IF vIdx = -1 THEN EXIT SUB

                  IF symbols(vIdx).SubIndex <> -1 THEN
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

                  subs(subCount).ReturnVarIdx = resolveSymbol(subName$)

                  tokIdx = nameIdx + 1
                  IF tokIdx < lineTokenCount THEN
                    IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
                      tokIdx = tokIdx + 1
                      DO WHILE tokIdx < lineTokenCount
                        argTok$ = lineTokens$(tokIdx)
                        IF retTokenVal(argTok$) = 256 + ASC(")") THEN EXIT DO
                        IF retTokenVal(argTok$) = 0 THEN
                          argName$ = UCASE$(argTok$)
                          vIdxArg = resolveSymbol(argName$)
                          IF vIdxArg = -1 THEN EXIT SUB

                          ' Flag as explicit so lookahead typing ignores it (bypass implicit lookahead resolution)
                          symbols(vIdxArg).IsExplicit = 1

                          ' FORCE ARGUMENTS GLOBAL TO ALLOW CALLER-CALLEE COMMUNICATION
                          symbols(vIdxArg).IsLocal = 0

                          IF tokIdx + 1 < lineTokenCount THEN
                            IF retTokenVal(lineTokens$(tokIdx + 1)) = 256 + ASC("(") THEN
                              IF tokIdx + 2 < lineTokenCount THEN
                                IF retTokenVal(lineTokens$(tokIdx + 2)) = 256 + ASC(")") THEN
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
                            IF retTokenVal(lineTokens$(tokIdx + 1)) = TOK_AS THEN
                              tokIdx = tokIdx + 2
                              IF tokIdx < lineTokenCount THEN
                                IF retTokenVal(lineTokens$(tokIdx)) = TOK_UNSIGNED THEN
                                  tokIdx = tokIdx + 1
                                  IF tokIdx < lineTokenCount THEN
                                    tType = retTokenVal(lineTokens$(tokIdx))

                                    SELECT CASE tType

                                      CASE TOK_BYTE
                                        symbols(vIdxArg).DataType = TYPE_UBYTE
                                      CASE TOK_INTEGER
                                        symbols(vIdxArg).DataType = TYPE_UINTEGER
                                      CASE TOK_LONG
                                        symbols(vIdxArg).DataType = TYPE_ULONG
                                      CASE TOK_INTEGER64
                                        symbols(vIdxArg).DataType = TYPE_UINT64
                                      CASE ELSE
                                        throwCompilerError "EXPECTED _BYTE, INTEGER, LONG, OR _INTEGER64 BUT GOT " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                                        EXIT SUB

                                    END SELECT ' tType

                                  ELSE
                                    throwCompilerError "EXPECTED TYPE AFTER _UNSIGNED", ASIS, 0
                                    EXIT SUB
                                  END IF
                                ELSE
                                  tType = retTokenVal(lineTokens$(tokIdx))

                                  SELECT CASE tType

                                    CASE TOK_LONG
                                      symbols(vIdxArg).DataType = TYPE_LONG
                                    CASE TOK_INTEGER
                                      symbols(vIdxArg).DataType = TYPE_INTEGER
                                    CASE TOK_BYTE
                                      symbols(vIdxArg).DataType = TYPE_BYTE
                                    CASE TOK_INTEGER64
                                      symbols(vIdxArg).DataType = TYPE_INTEGER64
                                    CASE TOK_SINGLE
                                      symbols(vIdxArg).DataType = TYPE_SINGLE
                                    CASE TOK_DOUBLE
                                      symbols(vIdxArg).DataType = TYPE_DOUBLE
                                    CASE TOK_DSTRING
                                      symbols(vIdxArg).DataType = TYPE_STRING
                                    CASE TOK_STRING
                                      symbols(vIdxArg).DataType = TYPE_STRING
                                      IF tokIdx + 1 < lineTokenCount THEN
                                        IF retTokenVal(lineTokens$(tokIdx + 1)) = 256 + ASC("*") THEN
                                          tokIdx = tokIdx + 2
                                          IF tokIdx < lineTokenCount THEN
                                            sizeTok$ = lineTokens$(tokIdx)
                                            isNum = 1
                                            FOR i_check = 1 TO LEN(sizeTok$)
                                              chCheck$ = MID$(sizeTok$, i_check, 1)
                                              IF chCheck$ < "0" OR chCheck$ > "9" THEN isNum = 0: EXIT FOR
                                            NEXT
                                            IF isNum = 0 THEN
                                              throwCompilerError "STRING LENGTH MUST BE CONSTANT", ASIS, 0
                                              EXIT SUB
                                            END IF
                                          ELSE
                                            throwCompilerError "EXPECTED STRING LENGTH", ASIS, 0
                                            EXIT SUB
                                          END IF
                                        ELSE
                                          throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                                          EXIT SUB
                                        END IF
                                      ELSE
                                        throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                                        EXIT SUB
                                      END IF
                                    CASE 0 ' UDT Identifier Match
                                      uTok$ = UCASE$(lineTokens$(tokIdx))
                                      matchedUdt = -1
                                      FOR iUdt = 0 TO udtCount - 1
                                        IF RTRIM$(udts(iUdt).RecordName) = uTok$ THEN
                                          matchedUdt = iUdt
                                          EXIT FOR
                                        END IF
                                      NEXT
                                      IF matchedUdt <> -1 THEN
                                        symbols(vIdxArg).DataType = TYPE_UDT
                                        symbols(vIdxArg).UDTIndex = matchedUdt
                                      ELSE
                                        throwCompilerError "UNSUPPORTED TYPE OR UNKNOWN UDT " + CHR$(34) + lineTokens$(tokIdx) + CHR$(34), ASIS, 0
                                        EXIT SUB
                                      END IF
                                    CASE ELSE
                                      throwCompilerError "UNSUPPORTED TYPE " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                                      EXIT SUB

                                  END SELECT ' tType

                                END IF
                              ELSE
                                throwCompilerError "EXPECTED TYPE AFTER AS", ASIS, 0
                                EXIT SUB
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
                          IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
                            tokIdx = tokIdx + 1
                          ELSE
                            IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(")") THEN
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
                IF retTokenVal(lineTokens$(1)) = TOK_SUB OR retTokenVal(lineTokens$(1)) = TOK_FUNCTION THEN
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

    subIdx = -1
    FOR iSub = 0 TO subCount - 1
      IF RTRIM$(subs(iSub).RecordName) = dName$ THEN
        subIdx = iSub
        EXIT FOR
      END IF
    NEXT

    IF subIdx <> -1 THEN
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

END SUB ' compilePass3Symbols

''''''''''''''''''''''''
SUB compilePass4ScanOrEmit

  ' Pass 4: Processes AST nodes and emits x64 machine code or builds intermediate IR
  ' Operates in blocks of 4 lines per cycle to yield back to the main UI loop
  ' Dummy mode tracks label offsets while the final mode writes the executable binary

  DIM tempSuccess AS LONG
  DIM isLabel AS LONG
  DIM stripLen AS LONG
  DIM tempStrip AS LONG
  DIM vIdx AS LONG
  DIM stmtRes AS LONG
  DIM vIdxEnd AS LONG
  DIM vIdxInstant AS LONG

  IF pass4.Line = 1 THEN defaultArrayDynamic = 0

  FOR loopCycle = 1 TO 4
    IF pass4.Line <= editor.LastLine THEN
      iy = pass4.Line
      currentLineNumber = iy

      curLine$ = compileText$(iy)
      tempLine$ = LTRIM$(RTRIM$(curLine$))

      IF LEN(tempLine$) > 0 THEN

        isLabel = 0
        labelStr$ = ""
        stripLen = 0

        firstChar$ = LEFT$(tempLine$, 1)
        IF firstChar$ >= "0" AND firstChar$ <= "9" THEN
          FOR i_check = 1 TO LEN(tempLine$)
            chCheck$ = MID$(tempLine$, i_check, 1)
            IF chCheck$ >= "0" AND chCheck$ <= "9" THEN
              labelStr$ = labelStr$ + chCheck$
              stripLen = stripLen + 1
            ELSE
              EXIT FOR
            END IF
          NEXT
          isLabel = 1
          IF stripLen < LEN(tempLine$) THEN
            IF MID$(tempLine$, stripLen + 1, 1) = ":" THEN
              stripLen = stripLen + 1
            END IF
          END IF
        ELSE
          uFirst$ = UCASE$(firstChar$)
          IF (uFirst$ >= "A" AND uFirst$ <= "Z") THEN
            tempStrip = 0
            tempLabel$ = ""
            FOR i_check = 1 TO LEN(tempLine$)
              chCheck$ = UCASE$(MID$(tempLine$, i_check, 1))
              IF (chCheck$ >= "A" AND chCheck$ <= "Z") OR (chCheck$ >= "0" AND chCheck$ <= "9") OR chCheck$ = "_" THEN
                tempLabel$ = tempLabel$ + chCheck$
                tempStrip = tempStrip + 1
              ELSE
                EXIT FOR
              END IF
            NEXT
            IF tempStrip < LEN(tempLine$) THEN
              IF MID$(tempLine$, tempStrip + 1, 1) = ":" THEN
                isLabel = 1
                labelStr$ = tempLabel$
                stripLen = tempStrip + 1
              END IF
            END IF
          END IF
        END IF

        IF isLabel = 1 THEN
          labelName$ = "%" + UCASE$(labelStr$)

          ' Find label and set offset
          expectedSymType = TYPE_LABEL
          vIdx = resolveSymbol(labelName$)
          IF vIdx <> -1 THEN
            symbols(vIdx).Offset = emitPos
            symbols(vIdx).IsExplicit = 1
          END IF

          ' Strip label for keyword scanning on the same line
          tempLine$ = LTRIM$(MID$(tempLine$, stripLen + 1))
        END IF

        IF LEN(tempLine$) > 0 THEN
          tokenizeLine tempLine$

          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            pass4.Success = 0
            EXIT SUB
          END IF

          IF lineTokenCount > 0 THEN

            isStackSpanning = 0
            FOR ii = 0 TO lineTokenCount - 1
              tVal = retTokenVal(lineTokens$(ii))
              IF tVal = TOK_SUB OR tVal = TOK_FUNCTION THEN
                isStackSpanning = 1
                EXIT FOR
              END IF
            NEXT

            t.TempCounter = 0 ' Ensure ephemeral TIRA tracking is reset for EVERY statement

            preStmtStackOffset = stack.currentStackOffset ' Snapshot the stack offset before compiling the statement

            stmtRes = parseStatement(0)
            IF stmtRes = 0 THEN
              pass4.Success = 0
              EXIT SUB
            END IF

            ' Catch hidden stack alignment bugs right at the source
            IF isStackSpanning = 0 THEN
              IF stack.currentStackOffset <> preStmtStackOffset THEN
                err$ = "FATAL: Stack alignment check failed at line " + retLineNumberStr$ + ". Offset: " + LTRIM$(STR$(stack.currentStackOffset)) + " bytes. Expected " + LTRIM$(STR$(preStmtStackOffset))
                ESCAPETEXT err$
              END IF
            END IF

            ' Reset the temporary heap after the statement has been completely evaluated
            ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, internalTempHeapStartSymbolIdx)
            ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, TEMP_HEAP_VAR_IDX)
            IF compilerFailed THEN pass4.Success = 0: EXIT SUB

          END IF
        END IF
      END IF

      pass4.Line = pass4.Line + 1
    ELSE
      ' Finalize Phase
      tempSuccess = pass4.Success

      IF tempSuccess = 1 THEN
        IF ctrlCount > 0 THEN
          addStatusMsg "ERROR: UNCLOSED BLOCK"
          tempSuccess = 0
        END IF
      END IF

      ' Validate that all GOTO targets exist
      IF tempSuccess = 1 THEN
        expectedSymType = TYPE_LABEL
        vIdxEnd = resolveSymbol("&END_PROGRAM")
        IF vIdxEnd <> -1 THEN symbols(vIdxEnd).DataType = TYPE_LABEL

        expectedSymType = TYPE_LABEL
        vIdxInstant = resolveSymbol("&INSTANT_EXIT")
        IF vIdxInstant <> -1 THEN symbols(vIdxInstant).DataType = TYPE_LABEL

        FOR ii = 0 TO gotoPatchCount - 1
          vIdx = gotoPatches(ii).VarIdx
          IF symbols(vIdx).DataType <> TYPE_LABEL THEN
            addStatusMsg "ERROR: LABEL " + RTRIM$(symbols(vIdx).RecordName) + " NOT FOUND"
            tempSuccess = 0
            EXIT FOR
          END IF
        NEXT
      END IF

      ' Validate that all CALL targets exist
      IF tempSuccess = 1 THEN
        FOR ii = 0 TO callPatchCount - 1
          targetName$ = RTRIM$(callPatches(ii).SubName)
          vIdx = resolveSymbol(targetName$)
          IF vIdx = -1 THEN
            tempSuccess = 0
            EXIT FOR
          END IF

          IF symbols(vIdx).SubIndex = -1 THEN
            addStatusMsg "ERROR: SUB " + targetName$ + " NOT FOUND"
            tempSuccess = 0
            EXIT FOR
          END IF
        NEXT
      END IF

      pass4.Success = tempSuccess
      pass4.SubState = 2 ' Mark as fully finalized
      EXIT FOR
    END IF
  NEXT

END SUB ' compilePass4ScanOrEmit

''''''''''''''''''''''''
SUB compilePass4bLocalVariables

  ' Pass 4B: Calculates memory footprints and byte offsets for local sub/function variables
  ' Runs just before x64 emission to ensure stack frames are aligned to the Windows ABI
  ' Global variables are handled later to account for temporary AST variable generation

  DIM sIdx AS LONG
  DIM localByteSize AS LONG
  DIM remainder AS LONG

  ' Local variable tracking
  ' Calculate LocalOffset for local variables and LocalFrameSize for each subroutine
  FOR iSub = 0 TO subCount - 1
    subs(iSub).LocalFrameSize = 0
  NEXT

  FOR ii = 0 TO symbolCount - 1
    IF symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0 THEN
      ' Find which sub this belongs to via ScopeID
      sIdx = -1
      FOR iSub = 0 TO subCount - 1
        IF subs(iSub).ScopeID = symbols(ii).ScopeID THEN
          sIdx = iSub
          EXIT FOR
        END IF
      NEXT

      IF sIdx <> -1 THEN
        ' Calculate the exact byte size this variable will demand on the stack
        localByteSize = retSymbolByteSize(ii)

        ' Assign offset and increment the subroutine's local frame size requirement
        symbols(ii).LocalOffset = subs(sIdx).LocalFrameSize
        subs(sIdx).LocalFrameSize = subs(sIdx).LocalFrameSize + localByteSize
      END IF
    END IF
  NEXT

  ' Enforce the 16-byte ABI stack alignment rule to lock in the final LocalFrameSize
  FOR iSub = 0 TO subCount - 1
    remainder = subs(iSub).LocalFrameSize MOD 16
    IF remainder <> 0 THEN
      subs(iSub).LocalFrameSize = subs(iSub).LocalFrameSize + (16 - remainder)
    END IF
  NEXT

END SUB ' compilePass4bLocalVariables

''''''''''''''''''''''''
SUB compilePass5GlobalMap

  ' Pass 5: Calculates final executable payload offsets for strings, variables, and descriptors
  ' This executes strictly after Pass 4 emission to guarantee that all ephemeral
  ' TIRA intermediate variables and AST temporaries are mapped into the data segment

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

END SUB ' compilePass5GlobalMap

''''''''''''''''''''''''
FUNCTION compilerFailed

  ' Returns 1 if a compiler error has been logged, allowing for cleaner error checking

  tempRet = 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN tempRet = 1
  compilerFailed = tempRet

END FUNCTION ' compilerFailed

''''''''''''''''''''''''
SUB confirmExit

  drawBorderBox (SCREENSIZEX \ 2) - 156, (SCREENSIZEY \ 2) - 20, 312, 40, 15, 0
  PrintStr (SCREENSIZEX \ 2) - 148, (SCREENSIZEY \ 2) - 4, "PRESS ESC TO CONFIRM, SPACE TO CANCEL", 14, 0
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

END FUNCTION ' cTrNum$'

''''''''''''''''''''''''
SUB deleteSelection

  IF editor.SelectStartX = editor.CursorX AND editor.SelectStartY = editor.CursorY THEN EXIT SUB

  IF editor.SelectStartY < editor.CursorY OR (editor.SelectStartY = editor.CursorY AND editor.SelectStartX < editor.CursorX) THEN
    startY = editor.SelectStartY: startX = editor.SelectStartX
    endY = editor.CursorY: endX = editor.CursorX
  ELSE
    startY = editor.CursorY: startX = editor.CursorX
    endY = editor.SelectStartY: endX = editor.SelectStartX
  END IF

  leftPart$ = LEFT$(editorText$(startY), startX)
  rightPart$ = MID$(editorText$(endY), endX + 1)

  editorText$(startY) = leftPart$ + rightPart$

  linesToRemove = endY - startY
  IF linesToRemove > 0 THEN
    FOR ii = startY + 1 TO EDITOR_LINE_MAX - linesToRemove
      editorText$(ii) = editorText$(ii + linesToRemove)
    NEXT
    FOR ii = EDITOR_LINE_MAX - linesToRemove + 1 TO EDITOR_LINE_MAX
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
FUNCTION determineExprType (startIdx, endIdx)

  DIM tVal AS LONG
  DIM firstChar AS STRING * 1
  DIM ii AS LONG
  DIM pDepth AS LONG
  DIM isValidEnclosure AS LONG
  DIM stripParens AS LONG
  DIM vName AS STRING
  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM retVarIdx AS LONG
  DIM dt AS LONG
  DIM tempRet AS LONG
  DIM suffix AS STRING * 1
  DIM charIdx AS LONG

  tempRet = TYPE_LONG
  stripParens = 0

  IF retTokenVal(lineTokens$(startIdx)) = 256 + ASC("(") THEN
    IF retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
      pDepth = 0
      isValidEnclosure = 1
      FOR ii = startIdx TO endIdx - 1
        tVal = retTokenVal(lineTokens$(ii))
        IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
        IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
        IF pDepth = 0 THEN
          isValidEnclosure = 0
          EXIT FOR
        END IF
      NEXT
      IF isValidEnclosure = 1 THEN stripParens = 1
    END IF
  END IF

  IF stripParens = 1 THEN
    tempRet = determineExprType(startIdx + 1, endIdx - 1)
    determineExprType = tempRet
    EXIT FUNCTION
  END IF

  IF startIdx < endIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx))
    IF tVal = 256 + ASC("-") OR tVal = TOK_NOT THEN
      tempRet = determineExprType(startIdx + 1, endIdx)
      determineExprType = tempRet
      EXIT FUNCTION
    END IF
  END IF

  tVal = retTokenVal(lineTokens$(startIdx))

  IF tVal = TOK_INKEYF OR tVal = TOK_INKEY THEN tempRet = TYPE_STRING: GOTO DET_EXIT

  ' Check intrinsic registry dynamically
  FOR ii = 0 TO intrinsicCount - 1
    IF tVal = intrinsicDefs(ii).TokenVal THEN
      tempRet = intrinsicDefs(ii).ReturnType
      GOTO DET_EXIT
    END IF
  NEXT

  IF tVal = 0 THEN
    firstChar = LEFT$(lineTokens$(startIdx), 1)
    IF firstChar = CHR$(34) THEN tempRet = TYPE_STRING: GOTO DET_EXIT
    IF (firstChar >= "0" AND firstChar <= "9") OR firstChar = "-" THEN
      IF INSTR(lineTokens$(startIdx), ".") > 0 OR INSTR(lineTokens$(startIdx), "#") > 0 OR INSTR(lineTokens$(startIdx), "!") > 0 THEN tempRet = TYPE_DOUBLE: GOTO DET_EXIT
      tempRet = TYPE_LONG: GOTO DET_EXIT
    END IF

    vName = UCASE$(lineTokens$(startIdx))
    vIdx = findSymbol(vName)

    IF vIdx <> -1 THEN
      subIdx = symbols(vIdx).SubIndex
      IF subIdx <> -1 THEN
        IF subs(subIdx).IsFunction = 1 THEN
          retVarIdx = subs(subIdx).ReturnVarIdx
          dt = symbols(retVarIdx).DataType
          IF dt = TYPE_STRING THEN tempRet = TYPE_STRING: GOTO DET_EXIT
          IF dt = TYPE_SINGLE THEN tempRet = TYPE_SINGLE: GOTO DET_EXIT
          IF dt = TYPE_DOUBLE THEN tempRet = TYPE_DOUBLE: GOTO DET_EXIT
          tempRet = TYPE_LONG: GOTO DET_EXIT
        END IF
      END IF

      dt = symbols(vIdx).DataType
      IF dt = TYPE_STRING THEN tempRet = TYPE_STRING: GOTO DET_EXIT
      IF dt = TYPE_SINGLE THEN tempRet = TYPE_SINGLE: GOTO DET_EXIT
      IF dt = TYPE_DOUBLE THEN tempRet = TYPE_DOUBLE: GOTO DET_EXIT
      tempRet = TYPE_LONG: GOTO DET_EXIT
    ELSE
      ' Symbol not found yet. Guess based on suffix rules.
      suffix = RIGHT$(vName, 1)
      IF suffix = "$" THEN tempRet = TYPE_STRING: GOTO DET_EXIT
      IF suffix = "#" THEN tempRet = TYPE_DOUBLE: GOTO DET_EXIT
      IF suffix = "!" THEN tempRet = TYPE_SINGLE: GOTO DET_EXIT
      IF suffix = "&" OR suffix = "%" THEN tempRet = TYPE_LONG: GOTO DET_EXIT

      charIdx = ASC(LEFT$(vName, 1)) - 65
      IF charIdx >= 0 AND charIdx <= 25 THEN
        IF defIntMap(charIdx) = 1 THEN tempRet = TYPE_LONG: GOTO DET_EXIT
      END IF

      tempRet = TYPE_SINGLE ' Default SINGLE
      GOTO DET_EXIT
    END IF
  END IF

  tempRet = TYPE_LONG

  DET_EXIT:
  determineExprType = tempRet

END FUNCTION ' determineExprType

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
  PrintStr btnSaveTxtX + 29, btnSaveTxtY + 6, "SAVE TXT", 15, -1

  btnLoadTxtW = 122
  btnLoadTxtH = 20
  btnLoadTxtX = btnSaveTxtX
  btnLoadTxtY = btnSaveTxtY + btnSaveTxtH + 8

  drawBorderBox btnLoadTxtX, btnLoadTxtY, btnLoadTxtW, btnLoadTxtH, 15, editor.windowBarClr
  PrintStr btnLoadTxtX + 29, btnLoadTxtY + 6, "LOAD TXT", 15, -1

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
  PrintStr btnCompileX + 33, btnCompileY + 6, "COMPILE", 15, -1

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
  PrintStr btnSearchX + 37, btnSearchY + 6, "SEARCH", 15, -1

  IF mouse.Released1 THEN
    IF mouseWithinBoxBounds(btnSaveTxtX, btnSaveTxtY, btnSaveTxtW, btnSaveTxtH) AND mouseDownWithinBoxBounds(btnSaveTxtX, btnSaveTxtY, btnSaveTxtW, btnSaveTxtH) THEN
      IF hasCode = 1 THEN
        editor.Focus = 1
        addStatusMsg "SAVING..."
        fileNameCode$ = "CODE.TXT"
        fileCodeSave
        addStatusMsg "SAVED"
      END IF
    END IF

    IF mouseWithinBoxBounds(btnLoadTxtX, btnLoadTxtY, btnLoadTxtW, btnLoadTxtH) AND mouseDownWithinBoxBounds(btnLoadTxtX, btnLoadTxtY, btnLoadTxtW, btnLoadTxtH) THEN
      editor.Focus = 1
      addStatusMsg "LOADING..."
      fileNameCode$ = "CODE.TXT"
      fileCodeLoad
      refineCode (0)
      editor.CursorX = 0
      editor.CursorY = 1
      editor.ScrollY = 1
      editor.ScrollX = 0
      addStatusMsg "LOADED"
    END IF

    IF mouseWithinBoxBounds(btnCompileX, btnCompileY, btnCompileW, btnCompileH) AND mouseDownWithinBoxBounds(btnCompileX, btnCompileY, btnCompileW, btnCompileH) THEN
      IF compileState = COMP_IDLE AND hasCode = 1 THEN
        editor.Focus = 1
        statusMsgCount = 0
        editor.StatusScrollY = 0
        editor.StatusSelectedIndex = -1
        FOR ii = 0 TO 999
          statusMsg$(ii) = ""
        NEXT
        compileState = COMP_REFINE
        addStatusMsg "REFINING..."
      END IF
    END IF

    IF mouseWithinBoxBounds(btnSearchX, btnSearchY, btnSearchW, btnSearchH) AND mouseDownWithinBoxBounds(btnSearchX, btnSearchY, btnSearchW, btnSearchH) THEN
      IF hasCode = 1 THEN
        editor.Focus = 1
        searchModal
      END IF
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
    PrintStr closeBtnX + 4, closeBtnY + 3, "?", 15, -1
  ELSE
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, -1
  END IF

  IF editor.TopMenuFocus = 4 OR isFullscreen = 0 THEN
    drawBorderBox blankX, blankY, blankW, blankH, 15, editor.windowBarClr
    IF mouseWithinBoxBounds(blankX, blankY, blankW, blankH) THEN
      drawClearBox blankX + 1, blankY + 1, blankW - 2, blankH - 2, 9
    END IF
    PrintStr blankX + 6, blankY + 3, "RES", 15, -1
  END IF

  IF editor.TopMenuFocus = 4 THEN
    drawBorderBox dropX, dropY, dropW, dropH, 15, editor.windowBarClr
    ' Use dropY + 1 and dropH - 1 for hit detection to keep Y=12 for the top row
    IF mouseWithinBoxBounds(dropX, dropY + 1, dropW, dropH - 1) THEN
      drawClearBox dropX + 1, dropY + 1, dropW - 2, dropH - 2, editor.CloseClr
    END IF
    PrintStr dropX + 6, dropY + 4, "END", 15, -1

    drawBorderBox minX, minY, minW, minH, 15, editor.windowBarClr
    ' Use minY + 1 and minH - 1 for hit detection to keep Y=12 for the top row
    IF mouseWithinBoxBounds(minX, minY + 1, minW, minH - 1) THEN
      drawClearBox minX + 1, minY + 1, minW - 2, minH - 2, 9
    END IF
    PrintChr minX + 4, minY + 4, CHR$(25), 15, -1

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
      tGoal = TIMER + 0.1: DO WHILE TIMER < tGoal: LOOP
      ESCAPETEXT "PROGRAM ENDED"
    END IF
  END IF

  IF mouse.Released1 THEN
    IF mouseWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) AND mouseDownWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
      IF editor.TopMenuFocus = 4 THEN
        editor.TopMenuFocus = 0
      ELSE
        editor.TopMenuFocus = 4
        editor.Focus = 0
      END IF
      editor.MenuClicked = 1
    END IF

    IF editor.TopMenuFocus = 4 OR isFullscreen = 0 THEN
      IF mouseWithinBoxBounds(blankX, blankY, blankW, blankH) AND mouseDownWithinBoxBounds(blankX, blankY, blankW, blankH) THEN
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
      IF mouseWithinBoxBounds(dropX, dropY + 1, dropW, dropH - 1) AND mouseDownWithinBoxBounds(dropX, dropY + 1, dropW, dropH - 1) THEN
        editor.MenuClicked = 1
        mouse.Released1 = 0
        ESCAPETEXT "PROGRAM ENDED"
      END IF

      IF mouseWithinBoxBounds(minX, minY + 1, minW, minH - 1) AND mouseDownWithinBoxBounds(minX, minY + 1, minW, minH - 1) THEN
        editor.MenuClicked = 1
        _SCREENICON
        editor.TopMenuFocus = 0
      END IF

      IF mouseWithinBoxBounds(SCREENSIZEX - 35, 0, 35, 27) AND mouseDownWithinBoxBounds(SCREENSIZEX - 35, 0, 35, 27) THEN editor.MenuClicked = 1
    END IF
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
  hScrollH = 10
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
  PrintChr hScrollX + 2, hScrollY, CHR$(17), 15, -1
  PrintChr hScrollX + hScrollW - 9, hScrollY, CHR$(16), 15, -1

  ' Calculate maxLen for horizontal scrolling
  maxLen = 0
  FOR iy = 1 TO editor.LastLine
    l = LEN(editorText$(iy))
    IF l > maxLen THEN maxLen = l
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

    PrintStr numPosX, editorBoxY + (iy * 10) + 1, numStr$, lineColor, -1


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
        PrintStr editorTextX, editorBoxY + (iy * 10) + 1, printText$, 15, -1
      END IF
    END IF
  NEXT

  IF editor.Focus = 1 THEN
    IF editor.CursorY >= editor.ScrollY AND editor.CursorY < editor.ScrollY + textRows THEN
      IF editor.CursorX >= editor.ScrollX AND editor.CursorX < editor.ScrollX + 56 THEN
        cursorPixelX = editorTextX + ((editor.CursorX - editor.ScrollX) * 8)
        cursorPixelY = editorBoxY + ((editor.CursorY - editor.ScrollY) * 10) + 1
        drawCursor = 1

        IF drawCursor = 1 THEN
          cursorBlink = INT(TIMER * 2) AND 1
          IF cursorBlink = 1 THEN
            PrintChr cursorPixelX, cursorPixelY, "*", 14, -1
          ELSE
            PrintChr cursorPixelX, cursorPixelY, "_", 14, -1
          END IF
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
        IF editorTextLastClickTime <> -1 AND (TIMER - editorTextLastClickTime) < 0.3 THEN
          editorTextLastClickTime = -1 ' Reset to prevent triple-click looping
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
          editorTextLastClickTime = TIMER
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

  IF editor.MenuMode = 0 THEN
    drawBorderBox scrollBarX, scrollBarY, scrollBarW, scrollBarH, 15, 0
    PrintChr scrollBarX + 1, scrollBarY + 2, CHR$(24), 15, -1
    PrintChr scrollBarX + 1, scrollBarY + scrollBarH - 9, CHR$(25), 15, -1

    maxLines = 12
    IF uiSubCount > maxLines THEN
      scrollRange = uiSubCount - maxLines
      thumbH = scrollBarH - 20
      thumbMaxH = thumbH
      thumbSize = (maxLines * thumbMaxH) \ uiSubCount
      IF thumbSize < 8 THEN thumbSize = 8
      thumbY = scrollBarY + 10 + ((funcScrollY * (thumbMaxH - thumbSize)) \ scrollRange)
      LINE (scrollBarX + 1, thumbY)-(scrollBarX + scrollBarW - 2, thumbY + thumbSize - 1), 15, BF
    ELSE
      LINE (scrollBarX + 1, scrollBarY + 10)-(scrollBarX + scrollBarW - 2, scrollBarY + scrollBarH - 11), 15, BF
    END IF

    PrintStr funcListBoxX + 25, funcListBoxY + 4, "GO TO TOP", 15, -1
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

        PrintStr funcListBoxX + RIGHT_BOX_SPACING, funcListBoxY + ((ii + 1) * 10) + 4, sOutName$, listColor, -1
      END IF
    NEXT
  ELSE
    PrintStr funcListBoxX + 15, funcListBoxY + 4, "CUT", 15, -1
    PrintStr funcListBoxX + 15, funcListBoxY + 14, "COPY", 15, -1
    PrintStr funcListBoxX + 15, funcListBoxY + 24, "PASTE", 15, -1
    PrintStr funcListBoxX + 15, funcListBoxY + 34, "CANCEL", 15, -1
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
    IF editor.MenuMode = 0 THEN
      IF uiSubCount > maxLines THEN
        IF mouseWithinBoxBounds(scrollBarX, thumbY, scrollBarW, thumbSize) THEN
          funcScrollDragActive = 1
          funcScrollDragOffsetY = mouse.PosY - thumbY
        ELSE
          IF mouseWithinBoxBounds(scrollBarX, scrollBarY + 10, scrollBarW, thumbMaxH) THEN
            IF mouse.PosY < thumbY THEN
              funcScrollY = funcScrollY - maxLines
              IF funcScrollY < 0 THEN funcScrollY = 0
            ELSE
              funcScrollY = funcScrollY + maxLines
              maxFuncScroll = uiSubCount - maxLines
              IF maxFuncScroll < 0 THEN maxFuncScroll = 0
              IF funcScrollY > maxFuncScroll THEN funcScrollY = maxFuncScroll
            END IF
          END IF
        END IF
      END IF

      IF mouseWithinBoxBounds(scrollBarX, scrollBarY, scrollBarW, 10) THEN
        funcScrollY = funcScrollY - 1
        IF funcScrollY < 0 THEN funcScrollY = 0
      END IF

      IF mouseWithinBoxBounds(scrollBarX, scrollBarY + scrollBarH - 10, scrollBarW, 10) THEN
        funcScrollY = funcScrollY + 1
        maxFuncScroll = uiSubCount - maxLines
        IF maxFuncScroll < 0 THEN maxFuncScroll = 0
        IF funcScrollY > maxFuncScroll THEN funcScrollY = maxFuncScroll
      END IF
    END IF
  END IF

  IF mouse.Button1Down AND funcScrollDragActive = 1 THEN
    IF uiSubCount > maxLines THEN
      newThumbY = mouse.PosY - funcScrollDragOffsetY
      trackSize = thumbMaxH - thumbSize
      IF trackSize > 0 THEN
        newScrollY = ((newThumbY - (scrollBarY + 10)) * scrollRange) \ trackSize
        IF newScrollY < 0 THEN newScrollY = 0
        IF newScrollY > scrollRange THEN newScrollY = scrollRange
        funcScrollY = newScrollY
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    funcScrollDragActive = 0

    IF editor.MenuMode = 1 THEN
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY, funcListBoxW, funcListBoxH) = 0 THEN
        editor.MenuMode = 0
      END IF
    END IF

    IF editor.MenuMode = 0 THEN
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY, funcListBoxW - 10, funcListBoxH) AND mouseDownWithinBoxBounds(funcListBoxX, funcListBoxY, funcListBoxW - 10, funcListBoxH) THEN
        clickRelY = mouse.PosY - (funcListBoxY + 3)
        IF clickRelY < 0 THEN clickRelY = 0
        clickedRow = clickRelY \ 10
        IF clickedRow = 0 THEN
          rowY = funcListBoxY + 3
          LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 11, rowY + 9), 1, BF
          PrintStr funcListBoxX + 25, rowY + 1, "GO TO TOP", 15, -1
          _DISPLAY
          tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

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
            PrintStr funcListBoxX + RIGHT_BOX_SPACING, rowY + 1, LEFT$(uiSubName$(subIdx), 13), 15, -1
            _DISPLAY
            tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

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
    ELSE
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY + 3, funcListBoxW, 10) AND mouseDownWithinBoxBounds(funcListBoxX, funcListBoxY + 3, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 3
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "CUT", 15, -1
        _DISPLAY
        tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

        undo_StateSave
        lastActionWasTyping = 0

        copyText$ = retEditorSelection$
        IF copyText$ <> "" THEN _CLIPBOARD$ = copyText$
        deleteSelection
        editor.IsSelecting = 0
        editor.MenuMode = 0
      END IF
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY + 13, funcListBoxW, 10) AND mouseDownWithinBoxBounds(funcListBoxX, funcListBoxY + 13, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 13
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "COPY", 15, -1
        _DISPLAY
        tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

        copyText$ = retEditorSelection$
        IF copyText$ <> "" THEN _CLIPBOARD$ = copyText$
        editor.MenuMode = 0
      END IF
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY + 23, funcListBoxW, 10) AND mouseDownWithinBoxBounds(funcListBoxX, funcListBoxY + 23, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 23
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "PASTE", 15, -1
        _DISPLAY
        tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

        undo_StateSave
        lastActionWasTyping = 0

        pasteClipboardText
        editor.MenuMode = 0
      END IF
      IF mouseWithinBoxBounds(funcListBoxX, funcListBoxY + 33, funcListBoxW, 10) AND mouseDownWithinBoxBounds(funcListBoxX, funcListBoxY + 33, funcListBoxW, 10) THEN
        rowY = funcListBoxY + 33
        LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 2, rowY + 9), 1, BF
        PrintStr funcListBoxX + 15, rowY + 1, "CANCEL", 15, -1
        _DISPLAY
        tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

        editor.MenuMode = 0
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
  drawBorderBox scrollBarX, scrollBarY, scrollBarW, scrollBarH, 15, 0

  PrintChr scrollBarX + 1, scrollBarY + 2, CHR$(24), 15, -1
  PrintChr scrollBarX + 1, scrollBarY + scrollBarH - 9, CHR$(25), 15, -1

  maxLines = (statusBoxH - 8) \ 10
  scrollRange = 0
  IF statusMsgCount > maxLines THEN
    scrollRange = statusMsgCount - maxLines
    thumbH = scrollBarH - 20
    thumbMaxH = thumbH
    thumbSize = (maxLines * thumbMaxH) \ statusMsgCount
    IF thumbSize < 8 THEN thumbSize = 8
    thumbY = scrollBarY + 10 + ((editor.StatusScrollY * (thumbMaxH - thumbSize)) \ scrollRange)
    LINE (scrollBarX + 1, thumbY)-(scrollBarX + scrollBarW - 2, thumbY + thumbSize - 1), 15, BF
  ELSE
    LINE (scrollBarX + 1, scrollBarY + 10)-(scrollBarX + scrollBarW - 2, scrollBarY + scrollBarH - 11), 15, BF
  END IF

  lineY = statusBoxY + 5
  linesDrawn = 0
  FOR ii = editor.StatusScrollY TO statusMsgCount - 1
    IF linesDrawn >= maxLines THEN EXIT FOR

    ' Highlight selected line if the status bar is focused
    IF ii = editor.StatusSelectedIndex AND editor.Focus = 2 THEN
      LINE (statusBoxX + 1, lineY - 1)-(scrollBarX - 1, lineY + 8), 1, BF
      PrintStr statusBoxX + LEFT_SPACING, lineY, statusMsg$(ii), 15, -1
    ELSE
      PrintStr statusBoxX + LEFT_SPACING, lineY, statusMsg$(ii), 14, -1
    END IF

    lineY = lineY + 10
    linesDrawn = linesDrawn + 1
  NEXT

  ' Mouse Processing Logic
  IF mouse.Wheel <> 0 THEN
    IF mouseWithinBoxBounds(statusBoxX, statusBoxY, statusBoxW + scrollBarW, statusBoxH) THEN
      editor.Focus = 2
      editor.StatusScrollY = editor.StatusScrollY + mouse.Wheel
      IF statusMsgCount > maxLines THEN
        IF editor.StatusScrollY > statusMsgCount - maxLines THEN editor.StatusScrollY = statusMsgCount - maxLines
      ELSE
        editor.StatusScrollY = 0
      END IF
      IF editor.StatusScrollY < 0 THEN editor.StatusScrollY = 0
    END IF
  END IF

  IF mouse.Clicked1 THEN
    IF mouseWithinBoxBounds(statusBoxX, statusBoxY, statusBoxW + scrollBarW, statusBoxH) THEN
      editor.Focus = 2
    END IF

    IF statusMsgCount > maxLines THEN
      IF mouseWithinBoxBounds(scrollBarX, thumbY, scrollBarW, thumbSize) THEN
        editor.StatusScrollDragActive = 1
        editor.StatusScrollDragOffsetY = mouse.PosY - thumbY
      ELSE
        IF mouseWithinBoxBounds(scrollBarX, scrollBarY + 10, scrollBarW, thumbMaxH) THEN
          IF mouse.PosY < thumbY THEN
            editor.StatusScrollY = editor.StatusScrollY - maxLines
            IF editor.StatusScrollY < 0 THEN editor.StatusScrollY = 0
          ELSE
            editor.StatusScrollY = editor.StatusScrollY + maxLines
            IF editor.StatusScrollY > scrollRange THEN editor.StatusScrollY = scrollRange
          END IF
        END IF
      END IF
    END IF

    IF mouseWithinBoxBounds(scrollBarX, scrollBarY, scrollBarW, 10) THEN
      editor.Focus = 2
      editor.StatusScrollY = editor.StatusScrollY - 1
      IF editor.StatusScrollY < 0 THEN editor.StatusScrollY = 0
    END IF

    IF mouseWithinBoxBounds(scrollBarX, scrollBarY + scrollBarH - 10, scrollBarW, 10) THEN
      editor.Focus = 2
      editor.StatusScrollY = editor.StatusScrollY + 1
      IF statusMsgCount > maxLines THEN
        IF editor.StatusScrollY > statusMsgCount - maxLines THEN editor.StatusScrollY = statusMsgCount - maxLines
      ELSE
        editor.StatusScrollY = 0
      END IF
    END IF
  END IF

  IF mouse.Button1Down AND editor.StatusScrollDragActive = 1 THEN
    IF statusMsgCount > maxLines THEN
      newThumbY = mouse.PosY - editor.StatusScrollDragOffsetY
      trackSize = thumbMaxH - thumbSize
      IF trackSize > 0 THEN
        newScrollY = ((newThumbY - (scrollBarY + 10)) * scrollRange) \ trackSize
        IF newScrollY < 0 THEN newScrollY = 0
        IF newScrollY > scrollRange THEN newScrollY = scrollRange
        editor.StatusScrollY = newScrollY
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    editor.StatusScrollDragActive = 0

    IF mouseWithinBoxBounds(statusBoxX, statusBoxY, statusBoxW, statusBoxH) AND mouseDownWithinBoxBounds(statusBoxX, statusBoxY, statusBoxW, statusBoxH) THEN
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
          editor.StatusSelectedIndex = -1
        END IF
      ELSE
        editor.StatusSelectedIndex = -1
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
    PrintStr 6, 3, "FILE", 15, -1

    clickedIdx = processDropdownMenu(4, 11, 2, fileMenu$())

    fnBoxX = 75
    fnBoxY = 11
    fnBoxW = 17 + (LEN(fileNameCode$) * 8)
    fnBoxH = 16

    LINE (fnBoxX, fnBoxY + 1)-(fnBoxX + fnBoxW - 2, fnBoxY + fnBoxH - 2), editor.windowBarClr, BF
    LINE (fnBoxX, fnBoxY)-(fnBoxX + fnBoxW - 1, fnBoxY), 15
    LINE (fnBoxX + fnBoxW - 1, fnBoxY)-(fnBoxX + fnBoxW - 1, fnBoxY + fnBoxH - 1), 15
    LINE (fnBoxX, fnBoxY + fnBoxH - 1)-(fnBoxX + fnBoxW - 1, fnBoxY + fnBoxH - 1), 15

    PrintStr 84, 15, fileNameCode$, 11, -1

    IF clickedIdx = 0 THEN
      editor.TopMenuFocus = 0
      fileOpenModal
    END IF
    IF clickedIdx = 1 THEN
      editor.TopMenuFocus = 0
      fileSaveModal
    END IF
  ELSE
    PrintStr 6, 3, "FILE", 15, -1
  END IF

  DIM editMenu$(0)
  IF undoState.Ready = 1 THEN
    editMenu$(0) = "UNDO"
  ELSE
    editMenu$(0) = "~UNDO"
  END IF

  IF editor.TopMenuFocus = 2 THEN
    drawClearBox 44, 1, 34, 11, 9
    PrintStr 46, 3, "EDIT", 15, -1

    clickedIdx = processDropdownMenu(44, 11, 1, editMenu$())
    IF clickedIdx = 0 THEN
      editor.TopMenuFocus = 0
      undo_StateRestore
    END IF
  ELSE
    PrintStr 46, 3, "EDIT", 15, -1
  END IF

  DIM viewMenu$(0)
  viewMenu$(0) = "VIEW SUBS"

  IF editor.TopMenuFocus = 3 THEN
    drawClearBox 84, 1, 34, 11, 9
    PrintStr 86, 3, "VIEW", 15, -1

    clickedIdx = processDropdownMenu(84, 11, 1, viewMenu$())
    IF clickedIdx = 0 THEN
      editor.TopMenuFocus = 0
      viewSubsModal
    END IF
  ELSE
    PrintStr 86, 3, "VIEW", 15, -1
  END IF

  ' Draw Editor Scrollbar
  drawBorderBox editorScrollBarX, editorScrollBarY, editorScrollBarW, editorScrollBarH, 15, 0
  PrintChr editorScrollBarX + 1, editorScrollBarY + 2, CHR$(24), 15, -1
  PrintChr editorScrollBarX + 1, editorScrollBarY + editorScrollBarH - 9, CHR$(25), 15, -1

  ' Draw Corner Box
  drawBorderBox editorScrollBarX, hScrollY, editorScrollBarW, 8, 15, 0

  lastLine = editor.LastLine
  IF editor.CursorY > lastLine THEN lastLine = editor.CursorY

  maxScroll = lastLine - 27
  IF maxScroll < 1 THEN maxScroll = 1

  thumbHEd = editorScrollBarH - 20
  IF maxScroll = 1 THEN
    thumbSizeEd = thumbHEd
    thumbYEd = editorScrollBarY + 10
  ELSE
    thumbSizeEd = (textRows * thumbHEd) \ lastLine
    IF thumbSizeEd < 8 THEN thumbSizeEd = 8
    thumbYEd = editorScrollBarY + 10 + (((editor.ScrollY - 1) * (thumbHEd - thumbSizeEd)) \ (maxScroll - 1))
  END IF

  LINE (editorScrollBarX + 1, thumbYEd)-(editorScrollBarX + editorScrollBarW - 2, thumbYEd + thumbSizeEd - 1), 15, BF

  ' Mouse Processing Logic
  IF mouse.Clicked1 THEN
    IF mouseWithinBoxBounds(editorScrollBarX, thumbYEd, editorScrollBarW, thumbSizeEd) THEN
      editor.Focus = 1
      editor.ScrollDragActive = 1
      editor.ScrollDragOffsetY = mouse.PosY - thumbYEd
    ELSE
      IF mouseWithinBoxBounds(editorScrollBarX, editorScrollBarY + 10, editorScrollBarW, thumbHEd) THEN
        editor.Focus = 1
        IF mouse.PosY < thumbYEd THEN
          editor.ScrollY = editor.ScrollY - textRows
          IF editor.ScrollY < 1 THEN editor.ScrollY = 1
        ELSE
          editor.ScrollY = editor.ScrollY + textRows
          IF editor.ScrollY > maxScroll THEN editor.ScrollY = maxScroll
        END IF
      END IF
    END IF

    IF mouseWithinBoxBounds(editorScrollBarX, editorScrollBarY, editorScrollBarW, 10) THEN
      editor.Focus = 1
      editor.ScrollY = editor.ScrollY - 1
      IF editor.ScrollY < 1 THEN editor.ScrollY = 1
    END IF

    IF mouseWithinBoxBounds(editorScrollBarX, editorScrollBarY + editorScrollBarH - 10, editorScrollBarW, 10) THEN
      editor.Focus = 1
      editor.ScrollY = editor.ScrollY + 1
      IF editor.ScrollY > maxScroll THEN editor.ScrollY = maxScroll
    END IF

    IF mouseWithinBoxBounds(editorScrollBarX, hScrollY, editorScrollBarW, 8) THEN
      editor.Focus = 1
      IF TIMER - cornerBoxLastClickTime < 0.25 THEN
        ' Double-click detected
        lastLine = editor.LastLine
        IF editor.CursorY > lastLine THEN lastLine = editor.CursorY

        maxScroll = lastLine - 27
        IF maxScroll < 1 THEN maxScroll = 1

        editor.ScrollY = maxScroll
        editor.CursorY = lastLine
        editor.CursorX = 0
        cornerBoxLastClickTime = -1 ' Reset for next double-click
      ELSE
        ' Single-click, set timer
        cornerBoxLastClickTime = TIMER
      END IF
    END IF

  END IF

  IF mouse.Button1Down AND editor.ScrollDragActive = 1 THEN
    IF maxScroll > 1 THEN
      newThumbY = mouse.PosY - editor.ScrollDragOffsetY
      trackSize = thumbHEd - thumbSizeEd
      IF trackSize > 0 THEN
        newScrollY = 1 + (((newThumbY - (editorScrollBarY + 10)) * (maxScroll - 1)) \ trackSize)
        IF newScrollY < 1 THEN newScrollY = 1
        IF newScrollY > maxScroll THEN newScrollY = maxScroll
        editor.ScrollY = newScrollY
      END IF
    END IF
  END IF

  IF mouse.Released1 THEN
    editor.ScrollDragActive = 0

    IF mouseWithinBoxBounds(4, 1, 32, 10) AND mouseDownWithinBoxBounds(4, 1, 32, 10) THEN
      IF editor.TopMenuFocus = 1 THEN
        editor.TopMenuFocus = 0
      ELSE
        editor.TopMenuFocus = 1
        editor.Focus = 0
      END IF
      editor.MenuClicked = 1
    END IF

    IF mouseWithinBoxBounds(44, 1, 32, 10) AND mouseDownWithinBoxBounds(44, 1, 32, 10) THEN
      IF editor.TopMenuFocus = 2 THEN
        editor.TopMenuFocus = 0
      ELSE
        editor.TopMenuFocus = 2
        editor.Focus = 0
      END IF
      editor.MenuClicked = 1
    END IF

    IF mouseWithinBoxBounds(84, 1, 32, 10) AND mouseDownWithinBoxBounds(84, 1, 32, 10) THEN
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
FUNCTION emitAstNode (nodeIdx, allowImplicit)

  DIM res AS LONG
  DIM leftNode AS LONG
  DIM rightNode AS LONG
  DIM res1 AS LONG
  DIM res2 AS LONG
  DIM leftIsFloat AS LONG
  DIM rightIsFloat AS LONG
  DIM opVal AS LONG
  DIM targetMode AS LONG
  DIM opModeFloat AS LONG
  DIM concatIdx AS INTEGER

  IF astNodes(nodeIdx).OpType = AST_LEAF THEN
    res = parseFactor(astNodes(nodeIdx).StartIdx, astNodes(nodeIdx).EndIdx, allowImplicit)
    emitAstNode = res
    EXIT FUNCTION
  END IF

  leftNode = astNodes(nodeIdx).LeftNode
  rightNode = astNodes(nodeIdx).RightNode

  res1 = emitAstNode(leftNode, allowImplicit)
  IF res1 = 0 THEN
    emitAstNode = 0
    EXIT FUNCTION
  END IF

  leftIsFloat = 0
  IF exprIs.DataType = TYPE_SINGLE THEN leftIsFloat = 1
  IF exprIs.DataType = TYPE_DOUBLE THEN leftIsFloat = 2

  IF leftIsFloat > 0 THEN
    ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
  END IF
  opPushReg 0

  res2 = emitAstNode(rightNode, allowImplicit)
  IF res2 = 0 THEN
    emitAstNode = 0
    EXIT FUNCTION
  END IF

  rightIsFloat = 0
  IF exprIs.DataType = TYPE_SINGLE THEN rightIsFloat = 1
  IF exprIs.DataType = TYPE_DOUBLE THEN rightIsFloat = 2

  IF rightIsFloat > 0 THEN
    ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
  END IF
  opPushReg 0

  opPopReg 3 ' Right operand goes to RBX
  opPopReg 0 ' Left operand goes to RAX

  opVal = astNodes(nodeIdx).OpType

  targetMode = MODE_SSE_DOUBLE
  IF leftIsFloat = 1 AND rightIsFloat = 1 THEN targetMode = MODE_SSE_SINGLE

  IF opVal = AST_CONCAT THEN
    concatIdx = resolveSymbol("!CONCAT" + cTrNum$(tempVarCounter) + "$")
    tempVarCounter = tempVarCounter + 1
    IF concatIdx = -1 THEN
      emitAstNode = 0
      EXIT FUNCTION
    END IF

    ff = genLoadStringDesc(0, 12, 13)
    ff = genLoadStringDesc(3, 10, 11)

    ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN emitAstNode = 0: EXIT FUNCTION

    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 13, 64)
    ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_REG, 11, 64)

    ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_REG, 8, 64)
    ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

    genBlockTransfer 12, 7, 13
    genBlockTransfer 10, 7, 11

    ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 14, 64, TEMP_HEAP_VAR_IDX)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN emitAstNode = 0: EXIT FUNCTION

    ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, concatIdx)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN emitAstNode = 0: EXIT FUNCTION

    ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_REG, 14, 64)
    ff = opMov(OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), OP_TYPE_REG, 8, 64)

    exprIs.DataType = TYPE_STRING
    exprIs.IsTemp = 1
  ELSE
    IF opVal = AST_AND OR opVal = AST_OR THEN
      IF leftIsFloat > 0 THEN
        ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        opModeFloat = MODE_SSE_DOUBLE
        IF leftIsFloat = 1 THEN opModeFloat = MODE_SSE_SINGLE
        ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opModeFloat)
      END IF
      IF rightIsFloat > 0 THEN
        ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 1, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
        opModeFloat = MODE_SSE_DOUBLE
        IF rightIsFloat = 1 THEN opModeFloat = MODE_SSE_SINGLE
        ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 3, OP_TYPE_REG, 1, opModeFloat)
      END IF

      IF opVal = AST_AND THEN ff = opALU(ALU_AND, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
      IF opVal = AST_OR THEN ff = opALU(ALU_OR, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)

      exprIs.DataType = TYPE_LONG
      exprIs.IsTemp = 0
    ELSE
      IF opVal = AST_IDIV THEN
        IF leftIsFloat > 0 THEN
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          opModeFloat = MODE_SSE_DOUBLE
          IF leftIsFloat = 1 THEN opModeFloat = MODE_SSE_SINGLE
          ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opModeFloat)
        END IF
        IF rightIsFloat > 0 THEN
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 1, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
          opModeFloat = MODE_SSE_DOUBLE
          IF rightIsFloat = 1 THEN opModeFloat = MODE_SSE_SINGLE
          ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 3, OP_TYPE_REG, 1, opModeFloat)
        END IF

        opExtend EXTEND_CQO
        ff = opUnary(UNARY_IDIV, OP_TYPE_REG, 3, 64)

        exprIs.DataType = TYPE_LONG
        exprIs.IsTemp = 0
      ELSE
        IF leftIsFloat > 0 OR rightIsFloat > 0 OR opVal = AST_POWER OR opVal = AST_DIV THEN
          targetMode = MODE_SSE_DOUBLE
          IF opVal <> AST_POWER THEN
            IF leftIsFloat = 1 AND rightIsFloat = 1 THEN targetMode = MODE_SSE_SINGLE
            IF leftIsFloat = 0 AND rightIsFloat = 0 AND opVal = AST_DIV THEN targetMode = MODE_SSE_SINGLE
          END IF

          IF leftIsFloat > 0 THEN
            ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
            IF leftIsFloat = 1 AND targetMode = MODE_SSE_DOUBLE THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
            END IF
          ELSE
            ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, targetMode)
          END IF

          IF rightIsFloat > 0 THEN
            ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 1, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
            IF rightIsFloat = 1 AND targetMode = MODE_SSE_DOUBLE THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 1, MODE_SSE_SINGLE)
            END IF
          ELSE
            ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 3, targetMode)
          END IF

          IF opVal = AST_POWER THEN
            ' Call pow() and ensure X64 ABI alignment
            ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 16, 64)
            ff = genAlignedCall(IAT_POW, 13, DEFAULT)
            ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, 16, 64)
          ELSE

            SELECT CASE opVal

              CASE AST_ADD: ff = opSSE(SSE_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
              CASE AST_SUB: ff = opSSE(SSE_SUB, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
              CASE AST_MUL: ff = opSSE(SSE_MUL, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)
              CASE AST_DIV: ff = opSSE(SSE_DIV, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)

            END SELECT ' opVal

          END IF

          IF targetMode = MODE_SSE_SINGLE THEN
            exprIs.DataType = TYPE_SINGLE
          ELSE
            exprIs.DataType = TYPE_DOUBLE
          END IF
          exprIs.IsTemp = 0
        ELSE

          SELECT CASE opVal

            CASE AST_ADD: ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
            CASE AST_SUB: ff = opALU(ALU_SUB, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
            CASE AST_MUL: ff = opImul(0, OP_TYPE_REG, 3, 0, MODE_IMUL64_REG)

          END SELECT ' opVal

          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 0
        END IF
      END IF
    END IF
  END IF

  emitAstNode = 1

END FUNCTION ' emitAstNode

''''''''''''''''''''''''
SUB emitByteCode (wByte AS _UNSIGNED _BYTE)

  IF isDummyPass = 1 THEN
    emitPos = emitPos + 1
    EXIT SUB
  END IF

  intermediateCode(emitPos) = wByte
  emitPos = emitPos + 1

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
SUB emitCRLF_Console

  ' Carriage return plus line feed
  ' If only a single LF was send, the cursor may drop down a line but staying at whatever horizontal position it was at

  ' Ensures the CRLF string slot exists, then emits x64 machine code to
  ' write CRLF to stdout. Caller must have saved the stdout handle at [rsp+48].

  IF crlfSlotIdx = -1 THEN
    crlfSlotIdx = resolveSymbol("!CRLF$")
    IF crlfSlotIdx = -1 THEN EXIT SUB
    strVarData$(crlfSlotIdx) = CHR$(13) + CHR$(10)
  END IF

  ' mov rcx, [rsp+slotHandleSave] ; reload stdout handle
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.slotHandleSave, 64)

  ' Load Descriptor Address into R12
  ff = genSymbolRouteMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RIP, 0, 64, crlfSlotIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ff = genLoadStringDesc(12, 2, 8)

  ' lea r9, [rsp+slotNumptrSpill]
  ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotNumptrSpill, 64)

  ' mov qword [rsp+slotOverlapped], 0
  ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)

  ' call WriteFile
  ff = opCall(IAT_WRITEFILE, CALLMODE_IAT)

END SUB ' emitCRLF_Console

''''''''''''''''''''''''
SUB emitCRLF_Graphics

  ' Newline

  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
  ' mov [!GFX_CUR_X], eax
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, resolveSymbol("!GFX_CUR_X"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ff = genSymbolRouteLea(0, resolveSymbol("!GFX_CUR_Y"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' Standard graphics uses 8 pixel lines
  ff = opALU(ALU_ADD, OP_TYPE_MEM_REG, 0, OP_TYPE_IMM, 8, 32)

END SUB ' emitCRLF_Graphics

''''''''''''''''''''''''
FUNCTION emitCoordinateExpr (startIdx, endIdx)

  ff = genForceNumericInt(startIdx, endIdx, "COORDINATE MUST BE NUMERIC")
  IF ff = 0 THEN
    emitCoordinateExpr = 0
    EXIT FUNCTION
  END IF

  emitCoordinateExpr = 1

END FUNCTION ' emitCoordinateExpr

''''''''''''''''''''''''
SUB emitDeepFreeArray (vIdx AS LONG)

  DIM dt AS LONG
  DIM elemSize AS LONG
  DIM lenIdx AS LONG
  DIM uIdx AS LONG
  DIM totalElems AS LONG
  DIM dynamicOffsets(64) AS LONG
  DIM numDynamicOffsets AS LONG
  DIM curOff AS LONG

  ' Free existing array if not NULL to prevent memory leaks from subsequent calls
  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, vIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
  jmpSkipFree = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  dt = symbols(vIdx).DataType
  numDynamicOffsets = 0
  elemSize = 8

  SELECT CASE dt

    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
    CASE TYPE_UDT
      elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
      uIdx = symbols(vIdx).UDTIndex

      FOR ii = 0 TO udts(uIdx).FieldCount - 1
        IF udtFields(uIdx, ii).DataType = TYPE_STRING AND udtFields(uIdx, ii).UDTIndex = 1 THEN
          dynamicOffsets(numDynamicOffsets) = udtFields(uIdx, ii).Offset
          numDynamicOffsets = numDynamicOffsets + 1
        END IF
      NEXT ' ii

    CASE TYPE_STRING
      lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
      IF floatVarData(lenIdx) > 0 THEN
        elemSize = floatVarData(lenIdx)
      ELSE
        elemSize = 8
        dynamicOffsets(0) = 0
        numDynamicOffsets = 1
      END IF

  END SELECT ' dt

  totalElems = symbols(vIdx).Size

  IF numDynamicOffsets > 0 THEN
    opPushReg 12
    opPushReg 14

    ff = opMov(OP_TYPE_REG, 12, OP_TYPE_REG, 1, 64)
    ff = opALU(ALU_XOR, OP_TYPE_REG, 14, OP_TYPE_REG, 14, 32)

    loopStartPos = emitPos
    ff = opALU(ALU_CMP, OP_TYPE_REG, 14, OP_TYPE_IMM, totalElems, 64)
    jmpEndDeepFree = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

    ' Calculate current element address: R11 = R12 + R14 * elemSize
    ff = opMov(OP_TYPE_REG, 11, OP_TYPE_REG, 14, 64)
    IF elemSize <> 1 THEN
      ff = opImul(11, OP_TYPE_REG, 11, elemSize, MODE_IMUL64_IMM32)
    END IF
    ff = opALU(ALU_ADD, OP_TYPE_REG, 11, OP_TYPE_REG, 12, 64)

    FOR iOff = 0 TO numDynamicOffsets - 1
      curOff = dynamicOffsets(iOff)

      ' Isolate the read safely to avoid 8-bit displacement limits on large UDTs
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 11, 64)
      IF curOff > 0 THEN
        ff = opALU(ALU_ADD, OP_TYPE_REG, 1, OP_TYPE_IMM, curOff, 64)
      END IF
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG, 1, 64)

      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpNextElem1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      opPushReg 1

      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG_DISP8, 1 + (16 * 256), 64)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 64)
      jmpFreeDesc1 = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 1, 64)
      ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
      jmpFreeDesc2 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
      ff = genAlignedCall(IAT_HEAPFREE, 15, DEFAULT)

      patch8 jmpFreeDesc1
      patch8 jmpFreeDesc2

      opPopReg 8

      ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
      ff = genAlignedCall(IAT_HEAPFREE, 15, DEFAULT)

      patch8 jmpNextElem1

    NEXT iOff

    opIncReg 14, 64
    ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, loopStartPos, JCC_TYPE_NEAR)

    patch32 jmpEndDeepFree, emitPos - (jmpEndDeepFree + 4)

    ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 12, 64)

    opPopReg 14
    opPopReg 12
  END IF

  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64) ' lpMem
  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX) ' hHeap
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32) ' dwFlags = 0
  ff = genAlignedCall(IAT_HEAPFREE, 13, DEFAULT)

  patch8 jmpSkipFree

END SUB ' emitDeepFreeArray

''''''''''''''''''''''''
SUB emitEpilogue

  epilogueStartPos = emitPos

  SELECT CASE compileHasGraphics

    CASE 0 ' Console epilogue

      ' PRINT "Press any key to continue..."
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, -11, 32)
      ff = opCall(IAT_GETSTDHANDLE, CALLMODE_IAT)
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)

      leaRdxPausePos = opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64)

      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 30, 32)
      ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotBytesWritten, 64)
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)

      ff = opCall(IAT_WRITEFILE, CALLMODE_IAT)

      ' SetConsoleMode to disable line input and echo
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, -10, 32)
      ff = opCall(IAT_GETSTDHANDLE, CALLMODE_IAT)
      ' Save hStdin for ReadFile
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotHandleSave, OP_TYPE_REG, 0, 64)

      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32) ' Mode 0
      ff = opCall(IAT_SETCONSOLEMODE, CALLMODE_IAT)

      ' ReadFile (Wait for key)
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.slotHandleSave, 64)

      ff = opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.slotReadBuffer, 64)
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 32)
      ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotBytesWritten, 64)
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)
      ff = opCall(IAT_READFILE, CALLMODE_IAT)

      ' Restore Console Mode to prevent terminal lockup
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.slotHandleSave, 64)
      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 503, 32) ' 0x01F7 Standard flags
      ff = opCall(IAT_SETCONSOLEMODE, CALLMODE_IAT)

      ' ExitProcess
      vIdxInstant = resolveSymbol("&INSTANT_EXIT")
      IF vIdxInstant <> -1 THEN
        symbols(vIdxInstant).DataType = TYPE_LABEL
        symbols(vIdxInstant).Offset = emitPos
      END IF

      vIdxExit = resolveSymbol("!EXIT_CODE")
      IF vIdxExit <> -1 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 32, vIdxExit)
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
      ELSE
        ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)
      END IF

      ff = opCall(IAT_EXITPROCESS, CALLMODE_IAT)

      ' Output the "Press any key..." string
      targetRVA = PE_TEXT_VA + emitPos
      pauseStr$ = CHR$(13) + CHR$(10) + "Press any key to continue..."
      FOR ii = 1 TO 30
        emitByteCode ASC(MID$(pauseStr$, ii, 1))
      NEXT

      patch32 leaRdxPausePos, targetRVA - (PE_TEXT_VA + leaRdxPausePos + 4)

    CASE 1 ' Graphics epilogue

      emitCRLF_Graphics
      emitCRLF_Graphics

      ' Print "Press any key to continue..."

      pauseStrIdx = resolveSymbol("!PAUSE_STR$")
      IF pauseStrIdx <> -1 THEN
        strVarData$(pauseStrIdx) = "Press any key to continue..."
        emitPrintString pauseStrIdx, 0
      END IF

      ' 1. Wait until NO keys are pressed
      releaseWaitStart = emitPos
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 10, 32)
      ff = opCall(IAT_SLEEP, CALLMODE_IAT)

      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)
      releaseLoopStart = emitPos
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)

      ' test ax, 0x8000
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)

      ' jnz .releaseWaitStart (If any key is pressed, start over)
      ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, releaseWaitStart, JCC_TYPE_NEAR)

      ' inc r15
      opIncReg 15, 64

      ' cmp r15, 255
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)

      ' jl .releaseLoopStart
      ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, releaseLoopStart, JCC_TYPE_NEAR)

      ' 2. Wait until ANY key is pressed
      pressWaitStart = emitPos
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 10, 32)
      ff = opCall(IAT_SLEEP, CALLMODE_IAT)

      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)
      pressLoopStart = emitPos
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)

      ' test ax, 0x8000
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)

      ' jnz .done
      jmpDonePos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' inc r15
      opIncReg 15, 64

      ' cmp r15, 255
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)

      ' jl .pressLoopStart
      ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, pressLoopStart, JCC_TYPE_NEAR)

      ' jmp .pressWaitStart
      ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, pressWaitStart, JCC_TYPE_NEAR)

      patch32 jmpDonePos, emitPos - (jmpDonePos + 4)

      ' ExitProcess
      vIdxInstant = resolveSymbol("&INSTANT_EXIT")
      IF vIdxInstant <> -1 THEN
        symbols(vIdxInstant).DataType = TYPE_LABEL
        symbols(vIdxInstant).Offset = emitPos
      END IF

      vIdxExit = resolveSymbol("!EXIT_CODE")
      IF vIdxExit <> -1 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 32, vIdxExit)
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
      ELSE
        ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)
      END IF

      ff = opCall(IAT_EXITPROCESS, CALLMODE_IAT)

  END SELECT ' compileHasGraphics

  metrics.EpilogueSize = emitPos - epilogueStartPos

END SUB ' emitEpilogue

''''''''''''''''''''''''
SUB emitGraphicsConsoleAppend

  ' 1. Check if buffer is full (GFX_BUFFER_ENTRIES entries)
  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_BUF_COUNT"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' cmp ecx, GFX_BUFFER_ENTRIES
  ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_IMM, GFX_BUFFER_ENTRIES, 32)

  ' jl .no_buf_shift
  jmpNoBufShiftPos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' cld
  opFlag FLAG_CLD

  ' lea rdi, [rip + gfxbufbase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64), -2, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov rsi, rdi
  ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 7, 64)

  ' add rsi, layout.GfxBufEntrySize
  ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_IMM, layout.GfxBufEntrySize, 64)

  ' mov rcx, 4095 * layout.GfxBufEntrySize
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 4095 * layout.GfxBufEntrySize, 64)

  genBlockTransfer 6, 7, 1

  ' mov ecx, 4095
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 4095, 32)

  ' mov [!GFX_BUF_COUNT], ecx
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 1, 32, resolveSymbol("!GFX_BUF_COUNT"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' .no_buf_shift:
  patch32 jmpNoBufShiftPos, emitPos - (jmpNoBufShiftPos + 4)

  ' 2. Check if _GFX_CUR_Y >= Bottom Row
  ' R11D = Bottom Row
  ff = opMov(OP_TYPE_REG, 11, OP_TYPE_IMM, gfxConfig.SizeY \ 8, 32)

  ' bot_y = R11D * 8
  opShift SHIFT_SHL, 11, 3, 32

  ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_CUR_Y"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' cmp edx, r11d
  ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_REG, 11, 32)

  ' jl .no_screen_scroll
  jmpNoScreenScrollPos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  '''' Do screen scroll
  ' R14D = Top Row (1 for full screen)
  ff = opMov(OP_TYPE_REG, 14, OP_TYPE_IMM, 1, 32)

  ' top_y = (R14D - 1) * 8
  opDecReg 14, 32
  opShift SHIFT_SHL, 14, 3, 32

  ' Use 8 pixel scroll for standard mode
  ' mov edx, r11d
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 11, 32)
  ' sub edx, 8
  ff = opALU(ALU_SUB, OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32)
  ' mov [!GFX_CUR_Y], edx
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 2, 32, resolveSymbol("!GFX_CUR_Y"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' cld
  opFlag FLAG_CLD

  ' Shift Framebuffer
  ' Dest = FramebufBase + top_y * SizeX
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64), -3, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ff = opMov(OP_TYPE_REG, 12, OP_TYPE_REG, 14, 32)
  ff = opImul(12, OP_TYPE_REG, 12, gfxConfig.SizeX, MODE_IMUL32_IMM32)
  ff = opALU(ALU_ADD, OP_TYPE_REG, 7, OP_TYPE_REG, 12, 64)

  ' Src = Dest + 8 * SizeX
  ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 7, 64)
  ff = opMov(OP_TYPE_REG, 13, OP_TYPE_IMM, 8 * gfxConfig.SizeX, 32)
  ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_REG, 13, 64)

  ' Count = (bot_y - top_y - 8) * SizeX
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 11, 32)
  ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_REG, 14, 32)
  ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_IMM, 8, 32)
  ff = opImul(1, OP_TYPE_REG, 1, gfxConfig.SizeX, MODE_IMUL32_IMM32)

  genBlockTransfer 6, 7, 1

  ' Clear bottom row (rdi is automatically advanced to the exact right spot by rep movsb)
  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

  ' mov ecx, r13d (8 * SizeX)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 32)

  ' rep stosb
  opString STR_STOS, REP_REP, 8

  ' Shift all text Y coordinates up by 8 if inside viewport boundaries
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64), -2, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_BUF_COUNT"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' test ecx, ecx
  ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)
  ' jz .skip_text_shift
  jmpSkipTextShift = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  shiftTextLoopPos = emitPos
  ' mov eax, [r8 + 20]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG_DISP8, 8 + (20 * 256), 32)

  ' cmp eax, r14d (top_y)
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 14, 32)
  ' jl .skip_this_text
  jmpSkipThisText1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' cmp eax, r11d (bot_y)
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 11, 32)
  ' jge .skip_this_text
  jmpSkipThisText2 = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' sub eax, 8
  ff = opALU(ALU_SUB, OP_TYPE_REG, 0, OP_TYPE_IMM, 8, 32)
  ' mov [r8 + 20], eax
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (20 * 256), OP_TYPE_REG, 0, 32)

  ' .skip_this_text:
  patch8 jmpSkipThisText1
  patch8 jmpSkipThisText2

  ' add r8, layout.GfxBufEntrySize
  ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_IMM, layout.GfxBufEntrySize, 64)
  ' dec ecx
  opDecReg 1, 32
  ' jnz shiftTextLoopPos
  ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, shiftTextLoopPos, JCC_TYPE_SHORT)

  patch8 jmpSkipTextShift

  ' .no_screen_scroll:
  patch32 jmpNoScreenScrollPos, emitPos - (jmpNoScreenScrollPos + 4)

  ' 3. Append new text entry
  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_BUF_COUNT"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64), -2, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov edx, ecx
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 1, 32)

  ' shl edx, layout.GfxBufEntryShift
  opShift SHIFT_SHL, 2, layout.GfxBufEntryShift, 32

  ' add r8, rdx
  ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_REG_ALT, 2, 64)

  ' push rcx (save line index)
  opPushReg 1

  '''' Store X and Y
  ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_CUR_X"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [r8 + 16], edx
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (16 * 256), OP_TYPE_REG, 2, 32)

  ' mov r11d, r9d
  ff = opMov(OP_TYPE_REG, 11, OP_TYPE_REG, 9, 32)

  ' shl r11d, 3
  opShift SHIFT_SHL, 11, 3, 32

  ' add edx, r11d
  ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_REG, 11, 32)

  ' mov [!GFX_CUR_X], edx
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 2, 32, resolveSymbol("!GFX_CUR_X"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_CUR_Y"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [r8 + 20], edx
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (20 * 256), OP_TYPE_REG, 2, 32)

  ' lea rax, [r8 + 24]
  ff = opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_REG_DISP8, 8 + (24 * 256), 64)

  ' mov [r8], rax
  ff = opMov(OP_TYPE_MEM_REG, 8, OP_TYPE_REG, 0, 64)

  ' mov [r8 + GFX_ENTRY_LEN_OFFSET], r9d
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (GFX_ENTRY_LEN_OFFSET * 256), OP_TYPE_REG, 9, 32)

  genBlockTransfer 10, 0, 9

  ' pop rcx (restore line index)
  opPopReg 1

  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_FG_RGB"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [r8 + 12], eax
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (12 * 256), OP_TYPE_REG, 0, 32)

  ' inc ecx
  opIncReg 1, 32

  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 1, 32, resolveSymbol("!GFX_BUF_COUNT"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  emitGraphicsRedraw

END SUB ' emitGraphicsConsoleAppend

''''''''''''''''''''''''
SUB emitGraphicsRedraw

  ' lea rax, [rip + HwndBase]
  ' RAX receives the memory address of the global window handle base
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -4, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov rcx, [rax]
  ' RCX receives the HWND (Window Handle) argument
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG, 0, 64)

  ' xor edx, edx
  ' RDX receives 0 (NULL for the RECT pointer, meaning the whole screen)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)

  ' mov r8d, 1
  ' R8 receives 1 (bErase = TRUE, forces background clear to prevent trailing dots)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 32)

  ' Call InvalidateRect cleanly with proper 16-byte stack alignment and 32-byte shadow space
  ff = genAlignedCall(IAT_INVALIDATERECT, 13, DEFAULT)

END SUB ' emitGraphicsRedraw

''''''''''''''''''''''''
SUB emitInput (vIdx, isStrVar AS LONG, wPrompt$)

  DIM pLen AS LONG
  DIM pStr$
  DIM targetType AS LONG

  SELECT CASE compileHasGraphics

    CASE 0 ' Console
      ' mov ecx, -10 (STD_INPUT_HANDLE)
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, -10, 32)
      ' call GetStdHandle
      ff = opCall(IAT_GETSTDHANDLE, CALLMODE_IAT)

      ' mov rcx, rax
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)

      ' Load TEMP heap pointer to R12
      ff = genSymbolRouteMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

      ' sub r12, 1024 (Allocate 1024 bytes for the input buffer safely)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 12, OP_TYPE_IMM, 1024, 64)

      ' mov rdx, r12
      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 12, 64)

      ' mov r8d, 1024 (Max input limit per read)
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 1024, 32)
      ' lea r9, [rsp+slotBytesWritten]
      ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotBytesWritten, 64)
      ' mov qword [rsp+slotOverlapped], 0
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)

      ' call ReadFile
      ff = opCall(IAT_READFILE, CALLMODE_IAT)

      ' mov rsi, r12
      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)

      ' mov rcx, [rsp+slotBytesWritten]
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.slotBytesWritten, 64)

    CASE 1 ' Graphics
      pLen = LEN(wPrompt$)
      IF pLen > 200 THEN pLen = 200
      pStr$ = LEFT$(wPrompt$, pLen)

      ' To echo the prompt cleanly in Graphics mode, we load it into the heap first
      promptLitIdx = resolveSymbol("!LIT" + cTrNum$(tempVarCounter) + "$")
      tempVarCounter = tempVarCounter + 1
      IF promptLitIdx = -1 THEN EXIT SUB
      strVarData$(promptLitIdx) = pStr$

      ' Load TEMP heap pointer to R12
      ff = genSymbolRouteMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

      ' sub r12, 1024 (Allocate 1024 bytes for the input buffer safely)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 12, OP_TYPE_IMM, 1024, 64)

      ' Get prompt descriptor
      ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, promptLitIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

      ' mov rsi, [rax] (Prompt DataAddress)
      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_MEM_REG, 0, 64)

      ' xor r13d, r13d
      ff = opALU(ALU_XOR, OP_TYPE_REG, 13, OP_TYPE_REG, 13, 32)

      ' mov r13, pLen
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_IMM, pLen, 64)

      genBlockTransfer 6, 12, 13

      ' Append the initial string to the graphics console immediately to echo as we type
      ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 12, 64)
      ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 13, 64)
      emitGraphicsConsoleAppend

      inputLoopStart = emitPos

      ' mov ecx, 10
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 10, 32)
      ' call Sleep
      ff = opCall(IAT_SLEEP, CALLMODE_IAT)

      ' mov r15, 8
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)

      keyLoopStart = emitPos

      ' mov rcx, r15
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)

      ' Save r12, r13, r15 to shadow space
      ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_REG, 12, 64)
      ff = opMov(OP_TYPE_MEM_RSP, 40, OP_TYPE_REG, 13, 64)
      ff = opMov(OP_TYPE_MEM_RSP, 48, OP_TYPE_REG, 15, 64)

      ' call GetAsyncKeyState
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)

      ' Restore r12, r13, r15
      ff = opMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RSP, 32, 64)
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_MEM_RSP, 40, 64)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_MEM_RSP, 48, 64)

      ' test ax, 0x8000
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)

      ' jz .next_key
      jmpNextKey1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 8
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)
      ' je .do_wait
      jmpDoWait1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 13
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 13, 64)
      ' je .do_wait
      jmpDoWait2 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 32
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 32, 64)
      ' jl .next_key
      jmpNextKey1b = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 126
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 126, 64)
      ' jg .next_key
      jmpNextKey1c = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' .do_wait:
      patch32 jmpDoWait1, emitPos - (jmpDoWait1 + 4)
      patch32 jmpDoWait2, emitPos - (jmpDoWait2 + 4)

      waitRelLoopStart = emitPos
      ' mov ecx, 10
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 10, 32)
      ' call Sleep
      ff = opCall(IAT_SLEEP, CALLMODE_IAT)

      ' mov rcx, r15
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)

      ' Save r12, r13, r15
      ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_REG, 12, 64)
      ff = opMov(OP_TYPE_MEM_RSP, 40, OP_TYPE_REG, 13, 64)
      ff = opMov(OP_TYPE_MEM_RSP, 48, OP_TYPE_REG, 15, 64)

      ' call GetAsyncKeyState
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)

      ' Restore r12, r13, r15
      ff = opMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RSP, 32, 64)
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_MEM_RSP, 40, 64)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_MEM_RSP, 48, 64)

      ' test ax, 0x8000
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)

      ' jnz .waitRelLoopStart
      ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, waitRelLoopStart, JCC_TYPE_NEAR)

      ' cmp r15, 13
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 13, 64)
      ' je .input_done
      jmpInputDone1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 8
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)
      ' jne .check_char
      jmpCheckChar = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' Prevent backspacing the prompt
      ' cmp r13, pLen
      ff = opALU(ALU_CMP, OP_TYPE_REG, 13, OP_TYPE_IMM, pLen, 64)

      ' jle .next_key
      jmpNextKey2 = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' dec r13
      opDecReg 13, 64

      ' jmp .do_redraw_update
      jmpNextKey3 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' .check_char:
      patch32 jmpCheckChar, emitPos - (jmpCheckChar + 4)

      ' mov r14, r15
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 15, 64)

      '''' Numpad mapping start
      ff = opALU(ALU_CMP, OP_TYPE_REG, 14, OP_TYPE_IMM, 96, 64)
      jmpSkipNumpad1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 14, OP_TYPE_IMM, 105, 64)
      jmpSkipNumpad2 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_SUB, OP_TYPE_REG, 14, OP_TYPE_IMM, 48, 64)

      patch8 jmpSkipNumpad1
      patch8 jmpSkipNumpad2
      '''' Numpad mapping end

      ' cmp r15, 32
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 32, 64)
      ' jl .next_key
      jmpNextKey4 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 126
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 126, 64)
      ' jg .next_key
      jmpNextKey5 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 65
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 65, 64)
      ' jl .store_char
      jmpStoreChar1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' cmp r15, 90
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 90, 64)
      ' jg .store_char
      jmpStoreChar2 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' Check shift
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 16, 32)
      ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_REG, 12, 64)
      ff = opMov(OP_TYPE_MEM_RSP, 40, OP_TYPE_REG, 13, 64)
      ff = opMov(OP_TYPE_MEM_RSP, 48, OP_TYPE_REG, 15, 64)
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)
      ff = opMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RSP, 32, 64)
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_MEM_RSP, 40, 64)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_MEM_RSP, 48, 64)

      ' test ax, 0x8000
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)
      ' jnz .store_char
      jmpStoreChar3 = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' add r14, 32
      ff = opALU(ALU_ADD, OP_TYPE_REG, 14, OP_TYPE_IMM, 32, 64)

      ' .store_char:
      patch32 jmpStoreChar1, emitPos - (jmpStoreChar1 + 4)
      patch32 jmpStoreChar2, emitPos - (jmpStoreChar2 + 4)
      patch32 jmpStoreChar3, emitPos - (jmpStoreChar3 + 4)

      ' mov [r12 + r13], r14b
      ff = opMov_SIB(1, OP_TYPE_REG, 14, 12, 13, 1, 0, 8)

      ' inc r13
      opIncReg 13, 64

      ' .do_redraw_update:
      redrawUpdatePos = emitPos

      ' lea rax, [rip + gfxBufCount]
      addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -1, 0
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

      ' mov ecx, [rax]
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG, 0, 32)

      ' dec ecx
      opDecReg 1, 32

      ' shl ecx, layout.GfxBufEntryShift
      opShift SHIFT_SHL, 1, layout.GfxBufEntryShift, 32

      ' lea r8, [rip + gfxBufBase]
      addPatch PATCH_GFX, opLea(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64), -2, 0
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

      ' add r8, rcx
      ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_REG_ALT, 1, 64)

      ' mov [r8 + GFX_ENTRY_LEN_OFFSET], r13d
      ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (GFX_ENTRY_LEN_OFFSET * 256), OP_TYPE_REG, 13, 32)

      '''' Copy string to gfx buff
      ' push rsi
      opPushReg 6
      ' push rdi
      opPushReg 7
      ' push rcx
      opPushReg 1

      ' lea rdi, [r8 + 24]
      ff = opLea(OP_TYPE_REG, 7, OP_TYPE_MEM_REG_DISP8, 8 + (24 * 256), 64)

      genBlockTransfer 12, 7, 13

      ' pop rcx
      opPopReg 1
      ' pop rdi
      opPopReg 7
      ' pop rsi
      opPopReg 6

      emitGraphicsRedraw

      ' .next_key:
      patch32 jmpNextKey1, emitPos - (jmpNextKey1 + 4)
      patch32 jmpNextKey1b, emitPos - (jmpNextKey1b + 4)
      patch32 jmpNextKey1c, emitPos - (jmpNextKey1c + 4)
      patch32 jmpNextKey2, emitPos - (jmpNextKey2 + 4)
      patch32 jmpNextKey3, redrawUpdatePos - (jmpNextKey3 + 4)
      patch32 jmpNextKey4, emitPos - (jmpNextKey4 + 4)
      patch32 jmpNextKey5, emitPos - (jmpNextKey5 + 4)

      ' inc r15
      opIncReg 15, 64

      ' cmp r15, 255
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)
      ' jl .key_loop
      ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, keyLoopStart, JCC_TYPE_NEAR)

      ' jmp .input_loop
      ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, inputLoopStart, JCC_TYPE_NEAR)

      ' .input_done:
      patch32 jmpInputDone1, emitPos - (jmpInputDone1 + 4)

      ' Setup rcx and rsi for shared conversion logic, stripping prompt from the extracted data
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)
      IF pLen > 0 THEN
        ' sub rcx, pLen
        ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_IMM, pLen, 64)
      END IF

      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)
      IF pLen > 0 THEN
        ' add rsi, pLen
        ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_IMM, pLen, 64)
      END IF

  END SELECT ' compileHasGraphics

  '''' Shared parsing logic
  IF isStrVar = 1 THEN
    ' mov rdi, rsi
    ff = opMov(OP_TYPE_REG, 7, OP_TYPE_REG, 6, 64)

    strLoopStart = emitPos
    ' test rcx, rcx
    ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)

    ' jle .str_done
    jmpStrDone1Pos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' lodsb
    opString STR_LODS, REP_NONE, 8
    ' cmp al, 13
    ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, 13, 8)

    ' je .str_done
    jmpStrDone2Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' cmp al, 10
    ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, 10, 8)

    ' je .str_done
    jmpStrDone3Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' stosb
    opString STR_STOS, REP_NONE, 8
    ' dec rcx
    opDecReg 1, 64

    ' jmp .str_loop
    ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, strLoopStart, JCC_TYPE_SHORT)

    ' .str_done:
    patch8 jmpStrDone1Pos
    patch8 jmpStrDone2Pos
    patch8 jmpStrDone3Pos

    ' Calculate final string length
    ' mov r8, rdi
    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 7, 64)
    ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 6, 64) ' mov r9, rsi
  ELSE
    ' Numeric
    ' xor eax, eax
    ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
    ' xor ebx, ebx
    ff = opALU(ALU_XOR, OP_TYPE_REG, 3, OP_TYPE_REG, 3, 32)
    ' xor edi, edi
    ff = opALU(ALU_XOR, OP_TYPE_REG, 7, OP_TYPE_REG, 7, 32)

    ' test rcx, rcx
    ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
    ' jz .num_done
    jmpNumDone1Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

    ' cmp byte [rsi], 45
    ff = opALU(ALU_CMP, OP_TYPE_MEM_REG, 6, OP_TYPE_IMM, 45, 8)

    ' jne .num_loop
    jmpNumLoopPos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' inc rdi
    opIncReg 7, 64
    ' inc rsi
    opIncReg 6, 64
    ' dec rcx
    opDecReg 1, 64

    numLoopStart = emitPos
    patch8 jmpNumLoopPos

    ' test rcx, rcx
    ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
    ' jz .num_done
    jmpNumDone2Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

    ' movzx rdx, byte [rsi]
    ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG, 6, MODE_MOVZX64_8)
    ' cmp dl, 13
    ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 13, 8)
    ' je .num_done
    jmpNumDone3Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

    ' cmp dl, 10
    ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 10, 8)
    ' je .num_done
    jmpNumDone4Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

    ' sub dl, 48
    ff = opALU(ALU_SUB, OP_TYPE_REG, 2, OP_TYPE_IMM, 48, 8)
    ' cmp dl, 9
    ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 9, 8)

    ' ja .num_skip
    jmpNumSkipPos = opJcc(JCC_JA, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' imul rax, 10
    ff = opImul(0, OP_TYPE_REG, 0, 10, MODE_IMUL64_IMM)
    ' add rax, rdx
    ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG_ALT, 2, 64)

    ' .num_skip:
    patch8 jmpNumSkipPos

    ' inc rsi
    opIncReg 6, 64
    ' dec rcx
    opDecReg 1, 64
    ' jmp .num_loop
    ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, numLoopStart, JCC_TYPE_NEAR)

    patch32 jmpNumDone1Pos, emitPos - (jmpNumDone1Pos + 4)
    patch32 jmpNumDone2Pos, emitPos - (jmpNumDone2Pos + 4)
    patch32 jmpNumDone3Pos, emitPos - (jmpNumDone3Pos + 4)
    patch32 jmpNumDone4Pos, emitPos - (jmpNumDone4Pos + 4)

    ' test rdi, rdi
    ff = opTest(OP_TYPE_REG, 7, OP_TYPE_REG, 7, 64)

    ' jz .num_store
    jmpNumStorePos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' neg rax
    ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)

    ' .num_store:
    patch8 jmpNumStorePos

    ' Automatically coerce to the destination numeric type to prevent IEEE 754 raw integer conversion errors
    targetType = symbols(vIdx).DataType
    IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
      ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      IF targetType = TYPE_SINGLE THEN
        ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE, vIdx)
      ELSE
        ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE, vIdx)
      END IF
    ELSE
      SELECT CASE targetType
        CASE TYPE_BYTE, TYPE_UBYTE
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 8, vIdx)
        CASE TYPE_INTEGER, TYPE_UINTEGER
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 16, vIdx)
        CASE TYPE_LONG, TYPE_ULONG
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, vIdx)
        CASE ELSE
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, vIdx)
      END SELECT
    END IF
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
  END IF

  IF isStrVar = 1 THEN
    ' Calculate final string length for descriptor: R8 = RDI - original_start
    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 7, 64)
    ff = opALU(ALU_SUB, OP_TYPE_REG, 8, OP_TYPE_REG, 12, 64)
    IF pLen > 0 AND compileHasGraphics = 1 THEN
      ff = opALU(ALU_SUB, OP_TYPE_REG, 8, OP_TYPE_IMM, pLen, 64)
    END IF

    ' DataAddress: original start -> R9
    ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 12, 64)
    IF pLen > 0 AND compileHasGraphics = 1 THEN
      ff = opALU(ALU_ADD, OP_TYPE_REG, 9, OP_TYPE_IMM, pLen, 64)
    END IF

    ' rcx = LHS Descriptor Ptr
    ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, vIdx)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
    isFixedStr = 0
    IF floatVarData(lenIdx) > 0 THEN isFixedStr = 1

    IF isFixedStr = 1 THEN
      ' Inline fixed string copy with truncation and space padding
      opPushReg 6 ' rsi
      opPushReg 7 ' rdi

      ' Dest DataAddress = [RCX]
      ff = opMov(OP_TYPE_REG, 7, OP_TYPE_MEM_REG, 1, 64)
      ' Dest Length = [RCX+8]
      ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG_DISP8, 1 + (8 * 256), 64)

      ' R11 = Dest Length (saved for padding calculations safely away from rep count)
      ff = opMov(OP_TYPE_REG, 11, OP_TYPE_REG, 10, 64)

      ' min(Dest Len, Src Len)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 10, OP_TYPE_REG, 8, 64)
      jmpSkipMin = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 8, 64)
      patch8 jmpSkipMin

      ' Copy min length bytes from R9 to R7
      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 9, 64)
      opPushReg 1
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 10, 64)
      opFlag FLAG_CLD
      opString STR_MOVS, REP_REP, 8
      opPopReg 1

      ' Pad spaces (R11 - min_len)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 11, OP_TYPE_REG, 10, 64)
      jmpSkipPad = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      opPushReg 1
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 11, 64)
      ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, 32, 8)
      opString STR_STOS, REP_REP, 8
      opPopReg 1
      patch8 jmpSkipPad

      opPopReg 7
      opPopReg 6
    ELSE
      ' Create fake RHS descriptor securely in the local stack frame scratchpad
      ' xor eax, eax
      ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

      ' MOV [RSP + stack.TMP_DESC_PTR + 16], RAX (Flags = 0)
      ff = opMov(OP_TYPE_MEM_RSP, stack.TMP_DESC_PTR + 16, OP_TYPE_REG, 0, 64)

      ' MOV [RSP + stack.TMP_DESC_PTR + 8], R8 (Length)
      ff = opMov(OP_TYPE_MEM_RSP, stack.TMP_DESC_PTR + 8, OP_TYPE_REG, 8, 64)

      ' MOV [RSP + stack.TMP_DESC_PTR + 0], R9 (DataAddress)
      ff = opMov(OP_TYPE_MEM_RSP, stack.TMP_DESC_PTR + 0, OP_TYPE_REG, 9, 64)

      ' LEA RDX, [RSP + stack.TMP_DESC_PTR] (RHS Descriptor Ptr)
      ff = opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.TMP_DESC_PTR, 64)

      ' Call RT_STR_ASSIGN
      addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
    END IF
  END IF

END SUB ' emitInput

''''''''''''''''''''''''
SUB emitLoadValue (wTok$)

  DIM dt AS LONG

  tVal = retTokenVal(wTok$)
  IF tVal = 0 THEN
    firstChar$ = LEFT$(wTok$, 1)
    IF (firstChar$ >= "0" AND firstChar$ <= "9") OR firstChar$ = "-" THEN
      IF INSTR(wTok$, ".") > 0 OR INSTR(wTok$, "#") > 0 OR INSTR(wTok$, "!") > 0 THEN
        vIdx = resolveSymbol("!FLTLIT" + cTrNum$(tempVarCounter))
        tempVarCounter = tempVarCounter + 1
        IF vIdx = -1 THEN EXIT SUB
        symbols(vIdx).DataType = TYPE_DOUBLE
        floatVarData(vIdx) = VAL(wTok$)
        ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_DOUBLE, vIdx)
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
        exprIs.DataType = TYPE_DOUBLE
        exprIs.IsTemp = 0
      ELSE
        ff = opMov(0, 0, 0, VAL(wTok$), MODE_IMM64)
        exprIs.DataType = TYPE_LONG
        exprIs.IsTemp = 0
      END IF
    ELSE
      IF firstChar$ = CHR$(34) THEN
        literal$ = extractQuotes$(wTok$)

        vIdx = resolveSymbol("!LIT" + cTrNum$(tempVarCounter) + "$")
        tempVarCounter = tempVarCounter + 1
        IF vIdx = -1 THEN EXIT SUB
        strVarData$(vIdx) = literal$

        ' Load descriptor pointer from VarBase
        ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, vIdx)
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
        exprIs.DataType = TYPE_STRING
        exprIs.IsTemp = 0
      ELSE
        vName$ = UCASE$(wTok$)
        vIdx = resolveSymbol(vName$)
        IF vIdx = -1 THEN EXIT SUB

        IF symbols(vIdx).DataType = TYPE_DOUBLE THEN
          ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_DOUBLE, vIdx)
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
          exprIs.DataType = TYPE_DOUBLE
          exprIs.IsTemp = 0
        ELSE
          IF symbols(vIdx).DataType = TYPE_SINGLE THEN
            ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_SINGLE, vIdx)
            IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
            exprIs.DataType = TYPE_SINGLE
            exprIs.IsTemp = 0
          ELSE
            IF symbols(vIdx).DataType = TYPE_STRING THEN
              ' Load descriptor pointer from VarBase
              ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, vIdx)
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
              exprIs.DataType = TYPE_STRING
              exprIs.IsTemp = 0
            ELSE
              dt = symbols(vIdx).DataType

              SELECT CASE dt

                CASE TYPE_BYTE
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVSX64_8, vIdx)
                CASE TYPE_UBYTE
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVZX64_8, vIdx)
                CASE TYPE_INTEGER
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVSX64_16, vIdx)
                CASE TYPE_UINTEGER
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVZX64_16, vIdx)
                CASE TYPE_LONG
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_MOVSXD, vIdx)
                CASE TYPE_ULONG
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 32, vIdx)
                CASE ELSE
                  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, vIdx)

              END SELECT ' dt

              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
              exprIs.DataType = TYPE_LONG
              exprIs.IsTemp = 0
            END IF
          END IF
        END IF
      END IF
    END IF
  END IF

END SUB ' emitLoadValue

''''''''''''''''''''''''
SUB emitPrintNumber (suppressNewline AS LONG)

  DIM isFloat AS LONG
  DIM opMode AS LONG
  DIM fmtIdx AS LONG

  isFloat = 0
  IF exprIs.DataType = TYPE_SINGLE THEN isFloat = 1
  IF exprIs.DataType = TYPE_DOUBLE THEN isFloat = 2

  IF isFloat > 0 THEN
    '''' sprintf path for floats

    ' The float is currently in XMM0 natively from parseExpression
    ' lea rcx, [rsp + stack.numItoaBuffer]
    ff = opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.numItoaBuffer, 64)

    IF isFloat = 1 THEN
      ' cvtss2sd xmm0, xmm0 (Promote SINGLE to DOUBLE for sprintf)
      ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
    END IF

    ' Variadic functions in Win64 require floats to be passed in both XMM and GPR
    ' arg 3 goes to xmm2 / r8

    ' movsd xmm2, xmm0
    ff = opSSE(SSE_MOV, OP_TYPE_REG, 2, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)

    ' movq r8, xmm0
    ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 8, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)

    ' Load descriptor pointer for !FMT_G$ into r12
    fmtIdx = resolveSymbol("!FMT_G$")
    IF fmtIdx = -1 THEN EXIT SUB

    ff = genSymbolRouteMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RIP, 0, 64, fmtIdx)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    ' mov rdx, [r12] (Data pointer to the null-terminated "%g" string)
    ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG, 12, 64)

    ' call sprintf
    ff = genAlignedCall(IAT_SPRINTF, 13, DEFAULT)

    ' rax now holds the length of the string
    ' lea r10, [rsp + stack.numItoaBuffer]
    ff = opLea(OP_TYPE_REG, 10, OP_TYPE_MEM_RSP, stack.numItoaBuffer, 64)

    ' mov [rsp+scratchStartPtr], r10
    ff = opMov(OP_TYPE_MEM_RSP, stack.scratchStartPtr, OP_TYPE_REG, 10, 64)

    ' mov r9, r10
    ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 10, 64)

    ' add r9, rax
    ff = opALU(ALU_ADD, OP_TYPE_REG, 9, OP_TYPE_REG, 0, 64)

    ' mov [rsp+scratchEndPtr], r9
    ff = opMov(OP_TYPE_MEM_RSP, stack.scratchEndPtr, OP_TYPE_REG, 9, 64)

  ELSE
    '''' itoa path for integers

    ' The integer is currently in RAX natively from parseExpression

    ' Use the local stack frame as a scratchpad instead of the permanent heap
    ' lea r10, [rsp + stack.numItoaBuffer]
    ff = opLea(OP_TYPE_REG, 10, OP_TYPE_MEM_RSP, stack.numItoaBuffer, 64)

    '''' itoa: convert rax to ascii in scratch slot

    ' add r10, 31 (point to end of a 32-byte chunk in the stack buffer)
    ff = opALU(ALU_ADD, OP_TYPE_REG, 10, OP_TYPE_IMM, 31, 64)

    ' mov r9, r10 ; end sentinel
    ff = opMov(OP_TYPE_REG, 9, OP_TYPE_REG, 10, 64)

    ' mov [rsp+scratchEndPtr], r9 ; save end pointer
    ff = opMov(OP_TYPE_MEM_RSP, stack.scratchEndPtr, OP_TYPE_REG, 9, 64)

    ' xor r12d, r12d
    ff = opALU(ALU_XOR, OP_TYPE_REG, 12, OP_TYPE_REG, 12, 32)
    ' test rax, rax
    ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)

    ' jns positive
    jmpPositivePos = opJcc(JCC_JNS, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' inc r12
    opIncReg 12, 64

    ' neg rax
    ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)

    ' positive:
    patch8 jmpPositivePos

    ' mov r11, 10
    ff = opMov(OP_TYPE_REG, 11, OP_TYPE_IMM, 10, 64)

    itoaLoopStart = emitPos
    ' xor edx, edx
    ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
    ' div r11
    ff = opUnary(UNARY_DIV, OP_TYPE_REG, 11, 64)
    ' add dl, 48
    ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, 48, 8)
    ' dec r10
    opDecReg 10, 64

    ' mov [r10], dl
    ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 2, 8)
    ' test rax, rax
    ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)

    ' jnz itoaLoopStart
    ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, itoaLoopStart, JCC_TYPE_SHORT)

    ' test r12, r12
    ff = opTest(OP_TYPE_REG, 12, OP_TYPE_REG, 12, 64)

    ' jz done
    jmpDonePos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' dec r10
    opDecReg 10, 64

    ' mov byte [r10], 45
    ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_IMM, 45, 8)

    ' done:
    patch8 jmpDonePos

    ' r10 = first digit pointer
    ' mov [rsp+scratchStartPtr], r10
    ff = opMov(OP_TYPE_MEM_RSP, stack.scratchStartPtr, OP_TYPE_REG, 10, 64)

  END IF

  '''' mode-specific output

  SELECT CASE compileHasGraphics

    CASE 0
      '''' console

      ' getstdhandle
      ' mov ecx, -11
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, -11, 32)
      ' call GetStdHandle
      ff = opCall(IAT_GETSTDHANDLE, CALLMODE_IAT)
      ' mov [rsp+slotHandleSave], rax ; save handle for crlf
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotHandleSave, OP_TYPE_REG, 0, 64)

      ' writefile(handle, digitstart, digitlen, &written, null)
      ' mov rcx, rax
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
      ' mov rdx, [rsp+scratchStartPtr] ; digit start
      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.scratchStartPtr, 64)
      ' mov r8, [rsp+scratchEndPtr] ; end pointer
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RSP, stack.scratchEndPtr, 64)

      ' sub r8, [rsp+scratchStartPtr] ; r8 = length
      ff = opALU(ALU_SUB, OP_TYPE_REG, 8, OP_TYPE_MEM_RSP, stack.scratchStartPtr, 64)

      ' lea r9, [rsp+slotNumptrSpill]
      ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotNumptrSpill, 64)
      ' mov qword [rsp+slotOverlapped], 0
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)
      ' call WriteFile
      ff = opCall(IAT_WRITEFILE, CALLMODE_IAT)

      IF suppressNewline = 0 THEN
        emitCRLF_Console
      END IF

    CASE 1
      '''' graphics

      ' mov r10, [rsp+scratchStartPtr] ; start pointer
      ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_RSP, stack.scratchStartPtr, 64)

      ' mov r9, [rsp+scratchEndPtr] ; end pointer
      ff = opMov(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.scratchEndPtr, 64)

      ' sub r9, r10 ; r9 = length
      ff = opALU(ALU_SUB, OP_TYPE_REG, 9, OP_TYPE_REG, 10, 64)

      emitGraphicsConsoleAppend

      IF suppressNewline = 0 THEN
        emitCRLF_Graphics
      END IF

  END SELECT ' compileHasGraphics

END SUB ' emitPrintNumber

''''''''''''''''''''''''
SUB emitPrintString (vIdx, suppressNewline AS LONG)

  ' Load Descriptor Address into R12
  ff = genSymbolRouteMov(OP_TYPE_REG, 12, OP_TYPE_MEM_RIP, 0, 64, vIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  SELECT CASE compileHasGraphics

    CASE 0 ' Console

      ' getstdhandle(std_output_handle)
      ' mov ecx, -11
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, -11, 32)
      ' call [rip + getstdhandle]
      ff = opCall(IAT_GETSTDHANDLE, CALLMODE_IAT)

      ' mov [rsp+slotHandleSave], rax ; save handle for crlf
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotHandleSave, OP_TYPE_REG, 0, 64)

      ' writefile(handle, strptr, strlen, &written, null)
      ' mov rcx, rax
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)

      ff = genLoadStringDesc(12, 2, 8)

      ' lea r9, [rsp+slotNumptrSpill]
      ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotNumptrSpill, 64)

      ' mov qword [rsp+slotOverlapped], 0
      ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)

      ' call [rip + writefile]
      ff = opCall(IAT_WRITEFILE, CALLMODE_IAT)

      IF suppressNewline = 0 THEN
        emitCRLF_Console
      END IF

    CASE 1 ' graphics

      ff = genLoadStringDesc(12, 10, 9)

      emitGraphicsConsoleAppend

      IF suppressNewline = 0 THEN
        emitCRLF_Graphics
      END IF

  END SELECT ' compileHasGraphics

END SUB ' emitPrintString

''''''''''''''''''''''''
SUB emitPrologue

  '''' Prologue
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, currentFrameSize, 64)

  ' Save the base stack pointer layout so the error handler knows where the stack began cleanly
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 4, 64, internalSafeRspSymbolIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' Register the Vectored Exception Handler Block
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 32)
  addPatch PATCH_RT, opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64), RT_VEH_HANDLER, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB
  ff = opCall(IAT_ADDVECTOREDEXCEPTIONHANDLER, CALLMODE_IAT)

  ' Call GetProcessHeap
  ff = opCall(IAT_GETPROCESSHEAP, CALLMODE_IAT)

  ' Save rax into !PROCESS_HEAP_PTR
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, PROCESS_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov rcx, rax (hHeap)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)

  ' mov edx, 8 (HEAP_ZERO_MEMORY)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32)

  ' mov r8d, 2097152 (dwBytes = 2MB total for temp heap)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, TEMP_HEAP_SIZE, 32)

  ' call HeapAlloc
  ff = opCall(IAT_HEAPALLOC, CALLMODE_IAT)

  ' Add TEMP_HEAP_SIZE to rax so it points to the END of the allocated block
  ' This allows string operations (like MID$) to safely subtract memory backwards
  ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_IMM, TEMP_HEAP_SIZE, 64)

  ' Save rax into !TEMP_HEAP_PTR
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, TEMP_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' Save rax into !TEMP_HEAP_START
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, internalTempHeapStartSymbolIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  metrics.PrologueSize = emitPos

END SUB ' emitPrologue

''''''''''''''''''''''''
SUB emitPrologueWindowSetup

  ' Sets up the Win64 window, registers the class, and starts the message loop for software rendering

  ' Software rendering mode only

  ' sub rsp, GFX_SETUP_FRAME
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_SETUP_FRAME, 64)

  '''' Initialize !GFX_FG_RGB to white
  ff = genSymbolRouteLea(0, resolveSymbol("!GFX_FG_RGB"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov dword [rax], 0x00FFFFFF
  ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_IMM, &HFFFFFF, 32)

  ''''
  ' Initialize RECT structure with client area size for AdjustWindowRectEx
  ' RECT: Left(4), Top(4), Right(4), Bottom(4)

  ' Left = 0
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 0, OP_TYPE_IMM, 0, 32)

  ' Top = 0
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 4, OP_TYPE_IMM, 0, 32)

  ' Calculate scaling factor for #GDOUBLE
  winScale = 1
  IF compileGraphicsDouble = 1 THEN winScale = 2

  ' Right = gfxConfig.SizeX * winScale
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 8, OP_TYPE_IMM, gfxConfig.SizeX * winScale, 32)

  ' Bottom = gfxConfig.SizeY * winScale
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 12, OP_TYPE_IMM, gfxConfig.SizeY * winScale, 32)

  ' Call AdjustWindowRectEx to calculate total window size
  ' BOOL AdjustWindowRectEx(LPRECT lpRect, DWORD dwStyle, BOOL bMenu, DWORD dwExStyle)

  ' lea rcx, [SETUP_SLOT_RECT]
  ff = opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT, 64)

  ' mov edx, 0x00CF0000 (WS_OVERLAPPEDWINDOW style)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, &HCF0000, 32)

  ' mov r8d, 0 (bMenu = FALSE)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 32)

  ' mov r9d, 0 (dwExStyle = 0)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 9, OP_TYPE_REG, 9, 32)

  ff = opCall(IAT_ADJUSTWINDOWRECTEX, CALLMODE_IAT)

  ' Calculate Width: Right - Left
  ' mov eax, [rsp + SETUP_SLOT_RECT + 8] (Right)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 8, 32)

  ' sub eax, [rsp + SETUP_SLOT_RECT + 0] (Left)
  ff = opALU(ALU_SUB, OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 0, 32)

  ' mov [rsp+SETUP_SLOT_NWIDTH], eax
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_NWIDTH, OP_TYPE_REG, 0, 32)

  ' Calculate Height: Bottom - Top
  ' mov eax, [rsp + SETUP_SLOT_RECT + 12] (Bottom)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 12, 32)

  ' sub eax, [rsp + SETUP_SLOT_RECT + 4] (Top)
  ff = opALU(ALU_SUB, OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_RECT + 4, 32)

  ' mov [rsp+SETUP_SLOT_NHEIGHT], eax
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_NHEIGHT, OP_TYPE_REG, 0, 32)

  '''' RegisterClassExA Setup
  ' xor ecx, ecx
  ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)
  ' call GetModuleHandleA
  ff = opCall(IAT_GETMODULEHANDLEA, CALLMODE_IAT)
  ' mov [rsp+SETUP_SLOT_HINSTANCE], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HINSTANCE, OP_TYPE_REG, 0, 64)

  ' mov dword [rsp+SETUP_SLOT_WNDCLASSEX], 80 (cbSize)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_WNDCLASSEX, OP_TYPE_IMM, 80, 32)
  ' mov dword [rsp+SETUP_SLOT_STYLE], 3 (style)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_STYLE, OP_TYPE_IMM, 3, 32)

  ' lea rax, [WndProc]
  leaWndProcPos = opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64)

  ' mov [rsp+SETUP_SLOT_LPFNWNDPROC], rax (lpfnWndProc)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_LPFNWNDPROC, OP_TYPE_REG, 0, 64)
  ' mov dword [rsp+SETUP_SLOT_CBCLSEXTRA], 0 (cbClsExtra)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_CBWNDEXTRA, OP_TYPE_IMM, 0, 32)
  ' mov dword [rsp+SETUP_SLOT_CBWNDEXTRA], 0 (cbWndExtra)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_CBWNDEXTRA, OP_TYPE_IMM, 0, 32)
  ' mov rax, [rsp+SETUP_SLOT_HINSTANCE]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HINSTANCE, 64)
  ' mov [rsp+SETUP_SLOT_WNDCLASSEX_HINSTANCE], rax (hInstance)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_WNDCLASSEX_HINSTANCE, OP_TYPE_REG, 0, 64)
  ' mov qword [rsp+SETUP_SLOT_HICON], 0 (hIcon)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HICON, OP_TYPE_IMM, 0, 64)
  ' LoadCursorA(NULL, IDC_ARROW)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32) ' xor ecx, ecx
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 32512, 32)
  ff = opCall(IAT_LOADCURSORA, CALLMODE_IAT)
  ' mov [rsp+SETUP_SLOT_HCURSOR], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HCURSOR, OP_TYPE_REG, 0, 64)

  ' GetStockObject(BLACK_BRUSH = 4)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 4, 32)
  ff = opCall(IAT_GETSTOCKOBJECT, CALLMODE_IAT)
  ' mov [rsp+SETUP_SLOT_HBRBACKGROUND], rax (hbrBackground)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HBRBACKGROUND, OP_TYPE_REG, 0, 64)

  ' mov qword [rsp+SETUP_SLOT_LPSZMENUNAME], 0 (lpszMenuName)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_LPSZMENUNAME, OP_TYPE_IMM, 0, 64)

  ' lea rax, [ClassName]
  leaClassName1Pos = opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64)

  ' mov [rsp+SETUP_SLOT_LPSZCLASSNAME], rax (lpszClassName)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_LPSZCLASSNAME, OP_TYPE_REG, 0, 64)

  ' hIconSm must be explicitly zeroed or the window class registration may fail
  ' mov qword [rsp+SETUP_SLOT_HICONSM], 0
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HICONSM, OP_TYPE_IMM, 0, 64)

  ' lea rcx, [rsp+SETUP_SLOT_WNDCLASSEX]
  ff = opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_WNDCLASSEX, 64)
  ' call RegisterClassExA
  ff = opCall(IAT_REGISTERCLASSEXA, CALLMODE_IAT)

  ' xor ecx, ecx (dwExStyle)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)

  ' lea rdx, [ClassName]
  leaClassName2Pos = opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64)

  ' lea r8, [WindowName]
  leaWindowNamePos = opLea(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64)

  ' mov r9d, 0x00CF0000
  ff = opMov(OP_TYPE_REG, 9, OP_TYPE_IMM, &HCF0000, 32)

  ' mov eax, 0x80000000 (CW_USEDEFAULT)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, &H80000000, 32)

  ' mov [rsp+SETUP_SLOT_X], eax (x)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_X, OP_TYPE_REG, 0, 32)

  ' mov [rsp+SETUP_SLOT_Y], eax (y)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_Y, OP_TYPE_REG, 0, 32)

  ' nWidth and nHeight are already set at the top of this function
  ' from the AdjustWindowRectEx calculation

  ' mov qword [rsp+SETUP_SLOT_HWNDPARENT], 0 (hWndParent)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HWNDPARENT, OP_TYPE_IMM, 0, 64)

  ' mov qword [rsp+SETUP_SLOT_HMENU], 0 (hMenu)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HMENU, OP_TYPE_IMM, 0, 64)
  ' mov rax, [rsp+SETUP_SLOT_HINSTANCE]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HINSTANCE, 64)

  ' mov [rsp+SETUP_SLOT_CREATE_HINSTANCE], rax (hInstance)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_CREATE_HINSTANCE, OP_TYPE_REG, 0, 64)

  ' mov qword [rsp+SETUP_SLOT_LPPARAM], 0 (lpParam)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_LPPARAM, OP_TYPE_IMM, 0, 64)

  ' call CreateWindowExA
  ff = opCall(IAT_CREATEWINDOWEXA, CALLMODE_IAT)

  ' mov [rsp+SETUP_SLOT_HWND], rax (save hwnd)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HWND, OP_TYPE_REG, 0, 64)

  '''' Disable Rounded Corners
  ' mov rcx, rax (HWND is still in RAX)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)

  ' mov edx, 33 (DWMWA_WINDOW_CORNER_PREFERENCE)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 33, 32)

  ' mov dword [rsp+SETUP_SLOT_HICONSM], 1 (DWMWCP_DONOTROUND)
  ff = opMov(OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HICONSM, OP_TYPE_IMM, 1, 32)

  ' lea r8, [rsp+SETUP_SLOT_HICONSM]
  ff = opLea(OP_TYPE_REG, 8, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HICONSM, 64)

  ' mov r9d, 4 (size of attribute)
  ff = opMov(OP_TYPE_REG, 9, OP_TYPE_IMM, 4, 32)

  ' call DwmSetWindowAttribute
  ff = opCall(IAT_DWMSETWINDOWATTRIBUTE, CALLMODE_IAT)

  ' mov rcx, [rsp+SETUP_SLOT_HWND]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HWND, 64)

  ' mov edx, 1
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 1, 32)

  ' call ShowWindow
  ff = opCall(IAT_SHOWWINDOW, CALLMODE_IAT)

  '''' Save HWND to global memory
  ' lea rdx, [rip + HwndBase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64), -4, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov rcx, [rsp+SETUP_SLOT_HWND]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.SETUP_SLOT_HWND, 64)

  ' mov [rdx], rcx
  ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 1, 64)

  '''' CreateThread
  ' xor ecx, ecx
  ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)
  ' xor edx, edx
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
  ' lea r8, [rip + UserCodeEntry]
  leaUserCodePos = opLea(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64)
  ' xor r9d, r9d
  ff = opALU(ALU_XOR, OP_TYPE_REG, 9, OP_TYPE_REG, 9, 32)
  ' mov qword [rsp+32], 0
  ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_IMM, 0, 64)
  ' mov qword [rsp+40], 0
  ff = opMov(OP_TYPE_MEM_RSP, 40, OP_TYPE_IMM, 0, 64)
  ' call CreateThread
  ff = opCall(IAT_CREATETHREAD, CALLMODE_IAT)

  '''' Message loop
  msgLoopTop = emitPos

  ' lea rcx, [rsp+disp32] (lpMsg)
  ff = opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.GRAPHICS_MSG_SLOT, 64)
  ' xor edx, edx (hWnd)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
  ' xor r8d, r8d (wMsgFilterMin)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 32)
  ' xor r9d, r9d (wMsgFilterMax)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 9, OP_TYPE_REG, 9, 32)
  ' mov dword [rsp+32], 1 (wRemoveMsg = PM_REMOVE)
  ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_IMM, 1, 32)

  ' call PeekMessageA
  ff = opCall(IAT_PEEKMESSAGEA, CALLMODE_IAT)

  ' test eax, eax
  ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

  ' jz no_message
  jzNoMessagePos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' cmp dword [rsp+disp32], 18 (WM_QUIT)
  ff = opALU(ALU_CMP, OP_TYPE_MEM_RSP, stack.GRAPHICS_MSG_SLOT + 8, OP_TYPE_IMM, 18, 32)

  ' je exit
  jeExitPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' lea rcx, [rsp+disp32]
  ff = opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.GRAPHICS_MSG_SLOT, 64)
  ' call TranslateMessage
  ff = opCall(IAT_TRANSLATEMESSAGE, CALLMODE_IAT)

  ' lea rcx, [rsp+disp32]
  ff = opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.GRAPHICS_MSG_SLOT, 64)
  ' call DispatchMessageA
  ff = opCall(IAT_DISPATCHMESSAGEA, CALLMODE_IAT)

  ' jmp msgLoopTop
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, msgLoopTop, JCC_TYPE_NEAR)

  ' no_message:
  noMessageTarget = emitPos
  patch32 jzNoMessagePos, noMessageTarget - (jzNoMessagePos + 4)

  ' mov ecx, 1
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 32)
  ' call Sleep
  ff = opCall(IAT_SLEEP, CALLMODE_IAT)

  ' jmp msgLoopTop
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, msgLoopTop, JCC_TYPE_NEAR)

  ' exit:
  exitTarget = emitPos
  patch32 jeExitPos, exitTarget - (jeExitPos + 4)

  ' ExitProcess
  ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_SETUP_FRAME, 64)
  ff = opCall(IAT_EXITPROCESS, CALLMODE_IAT)

  ' Strings
  classNameRVA = PE_TEXT_VA + emitPos
  ' "DefaultClass" + null (13 bytes)
  emitByteCode ASC("D"): emitByteCode ASC("e"): emitByteCode ASC("f"): emitByteCode ASC("a")
  emitByteCode ASC("u"): emitByteCode ASC("l"): emitByteCode ASC("t"): emitByteCode ASC("C")
  emitByteCode ASC("l"): emitByteCode ASC("a"): emitByteCode ASC("s"): emitByteCode ASC("s")
  emitByteCode 0

  windowNameRVA = PE_TEXT_VA + emitPos
  FOR ii = 1 TO LEN(compileWindowTitle$)
    emitByteCode ASC(MID$(compileWindowTitle$, ii, 1))
  NEXT
  emitByteCode 0

  fontFaceTerminalRVA = PE_TEXT_VA + emitPos
  ' "Terminal" + null
  emitByteCode ASC("T"): emitByteCode ASC("e"): emitByteCode ASC("r"): emitByteCode ASC("m")
  emitByteCode ASC("i"): emitByteCode ASC("n"): emitByteCode ASC("a"): emitByteCode ASC("l")
  emitByteCode 0

  ' Palette
  paletteRVA = PE_TEXT_VA + emitPos
  DIM palColor AS LONG
  FOR ii = 0 TO 255
    ' Standard SetPixel requires COLORREF format (0x00bbggrr -> Red, Green, Blue, Reserved)
    palColor = outputPal(ii, palRED)
    palColor = palColor + (outputPal(ii, palGREEN) * 256)
    palColor = palColor + (outputPal(ii, palBLUE) * 65536)
    emitBytes32 palColor
  NEXT

  ' WndProc
  wndProcRVA = PE_TEXT_VA + emitPos

  ' sub rsp, GFX_WNDPROC_FRAME
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_WNDPROC_FRAME, 64)

  ' mov [rsp+WNDPROC_SLOT_HWND], rcx
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HWND, OP_TYPE_REG, 1, 64)

  ' cmp edx, 2
  ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 2, 32)

  ' je .onDestroy
  jmpOnDestroyPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' cmp edx, 15
  ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 15, 32)

  ' je .onPaint
  jmpOnPaintPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' cmp edx, 258
  ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 258, 32)

  ' je .onChar
  jmpOnCharPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' cmp edx, 256
  ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 256, 32)

  ' je .onKeyDown
  jmpOnKeyDownPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' .onDefault:
  onDefaultTarget = emitPos
  ' call DefWindowProcA
  ff = opCall(IAT_DEFWINDOWPROCA, CALLMODE_IAT)

  ' add rsp, GFX_WNDPROC_FRAME
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_WNDPROC_FRAME, 64)

  ' ret
  opRet

  ' .onDestroy:
  onDestroyTarget = emitPos

  ' xor ecx, ecx
  ff = opALU(ALU_XOR, OP_TYPE_REG, 1, OP_TYPE_REG, 1, 32)

  ' call PostQuitMessage
  ff = opCall(IAT_POSTQUITMESSAGE, CALLMODE_IAT)

  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

  ' add rsp, GFX_WNDPROC_FRAME
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_WNDPROC_FRAME, 64)

  ' ret
  opRet

  ' .onPaint:
  onPaintTarget = emitPos
  ' lea rdx, [rsp+WNDPROC_SLOT_PAINTSTRUCT]
  ff = opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_PAINTSTRUCT, 64)

  ' mov rcx, [rsp+WNDPROC_SLOT_HWND]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HWND, 64)

  ' call BeginPaint
  ff = opCall(IAT_BEGINPAINT, CALLMODE_IAT)

  ' mov [rsp+WNDPROC_SLOT_HDC], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HDC, OP_TYPE_REG, 0, 64)

  '''' Create Memory DC
  ' mov rcx, [rsp+WNDPROC_SLOT_HDC]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HDC, 64)
  ' call CreateCompatibleDC
  ff = opCall(IAT_CREATECOMPATIBLEDC, CALLMODE_IAT)
  ' mov [rsp+WNDPROC_SLOT_MEMDC], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, OP_TYPE_REG, 0, 64)

  '''' Create Compatible Bitmap
  ' mov rcx, [rsp+WNDPROC_SLOT_HDC]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HDC, 64)
  ' mov rdx, gfxConfig.SizeX
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, gfxConfig.SizeX, 32)
  ' mov r8, gfxConfig.SizeY
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, gfxConfig.SizeY, 32)
  ' call CreateCompatibleBitmap
  ff = opCall(IAT_CREATECOMPATIBLEBITMAP, CALLMODE_IAT)
  ' mov [rsp+WNDPROC_SLOT_HBITMAP], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HBITMAP, OP_TYPE_REG, 0, 64)

  '''' Select Bitmap into Memory DC
  ' mov rcx, [rsp+WNDPROC_SLOT_MEMDC]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ' mov rdx, [rsp+WNDPROC_SLOT_HBITMAP]
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HBITMAP, 64)
  ' call SelectObject
  ff = opCall(IAT_SELECTOBJECT, CALLMODE_IAT)
  ' mov [rsp+WNDPROC_SLOT_OLD_HBITMAP], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_OLD_HBITMAP, OP_TYPE_REG, 0, 64)

  '''' Font selection
  leaFontFaceTerminalPos = opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 104, OP_TYPE_REG, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 96, OP_TYPE_IMM, 49, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 88, OP_TYPE_IMM, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 80, OP_TYPE_IMM, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 72, OP_TYPE_IMM, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 64, OP_TYPE_IMM, 255, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 56, OP_TYPE_IMM, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 48, OP_TYPE_IMM, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 40, OP_TYPE_IMM, 0, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_IMM, 400, 64)

  ' Reg Args
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 8, 32)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 0, 32)
  ff = opMov(OP_TYPE_REG, 9, OP_TYPE_IMM, 0, 32)

  ' Call CreateFontA
  ff = opCall(IAT_CREATEFONTA, CALLMODE_IAT)

  ' Save hFont safely into frame slot so it can be unhooked and safely cleared to prevent Windows memory leaks
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HFONT, OP_TYPE_REG, 0, 64)

  ' SelectObject(memDC, font)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ff = opCall(IAT_SELECTOBJECT, CALLMODE_IAT)

  ' Save old font
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_OLD_HFONT, OP_TYPE_REG, 0, 64)

  ' SetBkColor(memDC, 0)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
  ff = opCall(IAT_SETBKCOLOR, CALLMODE_IAT)

  '''' Framebuffer drawing loop to MEMDC (Slow SetPixel Approach)
  ' mov dword [rsp+WNDPROC_SLOT_FB_X], 0
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_X, OP_TYPE_IMM, 0, 32)

  ' mov dword [rsp+WNDPROC_SLOT_FB_Y], 0
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_Y, OP_TYPE_IMM, 0, 32)

  ' lea rax, [rip + FramebufBase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -3, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [rsp+WNDPROC_SLOT_FB_PTR], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_PTR, OP_TYPE_REG, 0, 64)

  fbLoopStartPos = emitPos

  ' mov eax, dword [rsp+WNDPROC_SLOT_FB_Y]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_Y, 32)

  ' cmp eax, gfxConfig.SizeY
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, gfxConfig.SizeY, 32)

  ' jge .fb_loop_end
  jmpFbLoopEndPos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' mov rcx, [rsp+WNDPROC_SLOT_FB_PTR]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_PTR, 64)

  ' movzx r9d, byte [rcx]
  ff = opMov(OP_TYPE_REG, 9, OP_TYPE_MEM_REG, 1, MODE_MOVZX32_8)

  ' test r9d, r9d
  ff = opTest(OP_TYPE_REG, 9, OP_TYPE_REG, 9, 32)

  ' jz .fb_skip_pixel
  jmpFbSkipPixelPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' lea r10, [rip + palette]
  leaPaletteFbPos = opLea(OP_TYPE_REG, 10, OP_TYPE_MEM_RIP, 0, 64)

  ' mov r9d, [r10 + r9*4]
  ff = opMov_SIB(0, OP_TYPE_REG, 9, 10, 9, 4, 0, 32)

  ' mov rcx, [rsp+WNDPROC_SLOT_MEMDC]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)

  ' mov edx, dword [rsp+WNDPROC_SLOT_FB_X]
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_X, 32)

  ' mov r8d, dword [rsp+WNDPROC_SLOT_FB_Y]
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_Y, 32)

  ' Draw to the memory storage layer without scaling
  ff = opCall(IAT_SETPIXEL, CALLMODE_IAT)

  ' .fb_skip_pixel:
  patch32 jmpFbSkipPixelPos, emitPos - (jmpFbSkipPixelPos + 4)

  ' mov rcx, [rsp+WNDPROC_SLOT_FB_PTR]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_PTR, 64)

  ' inc rcx
  opIncReg 1, 64

  ' mov [rsp+WNDPROC_SLOT_FB_PTR], rcx
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_PTR, OP_TYPE_REG, 1, 64)

  ' mov eax, dword [rsp+WNDPROC_SLOT_FB_X]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_X, 32)

  ' inc eax
  opIncReg 0, 32

  ' cmp eax, gfxConfig.SizeX
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, gfxConfig.SizeX, 32)

  ' jl .fb_x_no_wrap
  jmpFbXNoWrapPos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

  ' mov dword [rsp+WNDPROC_SLOT_FB_X], eax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_X, OP_TYPE_REG, 0, 32)

  ' mov eax, dword [rsp+WNDPROC_SLOT_FB_Y]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_Y, 32)

  ' inc eax
  opIncReg 0, 32

  ' mov dword [rsp+WNDPROC_SLOT_FB_Y], eax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_Y, OP_TYPE_REG, 0, 32)

  ' jmp .fb_loop_start
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, fbLoopStartPos, JCC_TYPE_NEAR)

  ' .fb_x_no_wrap:
  patch32 jmpFbXNoWrapPos, emitPos - (jmpFbXNoWrapPos + 4)

  ' mov dword [rsp+WNDPROC_SLOT_FB_X], eax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_FB_X, OP_TYPE_REG, 0, 32)

  ' jmp .fb_loop_start
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, fbLoopStartPos, JCC_TYPE_NEAR)

  ' .fb_loop_end:
  patch32 jmpFbLoopEndPos, emitPos - (jmpFbLoopEndPos + 4)

  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 32, resolveSymbol("!GFX_BUF_COUNT"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [rsp+WNDPROC_SLOT_COUNT], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_COUNT, OP_TYPE_REG, 0, 64)

  ' test eax, eax
  ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

  ' jz .end_loop
  jmpEndLoopPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' lea rax, [rip + gfxBufBase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -2, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [rsp+WNDPROC_SLOT_BASE], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_BASE, OP_TYPE_REG, 0, 64)

  loopStartPos = emitPos

  '''' SetTextColor from gfxBuf
  ' mov rcx, [rsp+WNDPROC_SLOT_MEMDC]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)

  ' mov rax, [rsp+WNDPROC_SLOT_BASE]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_BASE, 64)

  ' mov edx, [rax + 12] (Color)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG_DISP8, 0 + (12 * 256), 32)

  ' call SetTextColor
  ff = opCall(IAT_SETTEXTCOLOR, CALLMODE_IAT)

  '''' TextOutA
  ' mov rcx, [rsp+WNDPROC_SLOT_MEMDC]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)

  ' mov rax, [rsp+WNDPROC_SLOT_BASE]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_BASE, 64)

  ' mov edx, [rax + 16]
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG_DISP8, 0 + (16 * 256), 32)

  ' mov r8d, [rax + 20]
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG_DISP8, 0 + (20 * 256), 32)

  ' lea r9, [rax + 24] (Inline dynamic payload pointer completely neutralizes dangling pointer array shifts)
  ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_REG_DISP8, 0 + (24 * 256), 64)

  ' mov eax, [rax + GFX_ENTRY_LEN_OFFSET]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG_DISP8, 0 + (GFX_ENTRY_LEN_OFFSET * 256), 32)

  ' mov [rsp+32], rax
  ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_REG, 0, 64)

  ' call TextOutA
  ff = opCall(IAT_TEXTOUTA, CALLMODE_IAT)

  ' mov rax, [rsp+WNDPROC_SLOT_BASE]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_BASE, 64)
  ' add rax, layout.GfxBufEntrySize
  ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_IMM, layout.GfxBufEntrySize, 64)

  ' mov [rsp+WNDPROC_SLOT_BASE], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_BASE, OP_TYPE_REG, 0, 64)

  ' mov rax, [rsp+WNDPROC_SLOT_COUNT]
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_COUNT, 64)
  ' dec rax
  opDecReg 0, 64
  ' mov [rsp+WNDPROC_SLOT_COUNT], rax
  ff = opMov(OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_COUNT, OP_TYPE_REG, 0, 64)

  ' test rax, rax
  ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)

  ' jnz loopStartPos
  ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, loopStartPos, JCC_TYPE_NEAR)

  endLoopTarget = emitPos
  patch32 jmpEndLoopPos, endLoopTarget - (jmpEndLoopPos + 4)

  '''' Handle Window Transfer Logic
  winScale = 1
  IF compileGraphicsDouble = 1 THEN winScale = 2

  '''' StretchBlt the MEMDC to HDC scaling everything uniformly
  ' [RSP+80] = 0x00CC0020
  ff = opMov(OP_TYPE_MEM_RSP, 80, OP_TYPE_IMM, &H00CC0020, 32)
  ' [RSP+72] = SrcHeight
  ff = opMov(OP_TYPE_MEM_RSP, 72, OP_TYPE_IMM, gfxConfig.SizeY, 32)
  ' [RSP+64] = SrcWidth
  ff = opMov(OP_TYPE_MEM_RSP, 64, OP_TYPE_IMM, gfxConfig.SizeX, 32)
  ' [RSP+56] = 0
  ff = opMov(OP_TYPE_MEM_RSP, 56, OP_TYPE_IMM, 0, 32)
  ' [RSP+48] = 0
  ff = opMov(OP_TYPE_MEM_RSP, 48, OP_TYPE_IMM, 0, 32)
  ' [RSP+40] = memDC
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ff = opMov(OP_TYPE_MEM_RSP, 40, OP_TYPE_REG, 0, 64)

  ' [RSP+32] = DestHeight
  ff = opMov(OP_TYPE_MEM_RSP, 32, OP_TYPE_IMM, gfxConfig.SizeY * winScale, 32)

  ' R9 = DestWidth
  ff = opMov(OP_TYPE_REG, 9, OP_TYPE_IMM, gfxConfig.SizeX * winScale, 32)

  ' R8 = 0
  ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 32)

  ' RDX = 0
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)

  ' RCX = hdc
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HDC, 64)

  ' call StretchBlt
  ff = opCall(IAT_STRETCHBLT, CALLMODE_IAT)

  '''' Cleanup DC
  ' SelectObject(memDC, oldFont)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_OLD_HFONT, 64)
  ff = opCall(IAT_SELECTOBJECT, CALLMODE_IAT)

  ' DeleteObject(hFont)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HFONT, 64)
  ff = opCall(IAT_DELETEOBJECT, CALLMODE_IAT)

  ' SelectObject(memDC, oldBitmap)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_OLD_HBITMAP, 64)
  ff = opCall(IAT_SELECTOBJECT, CALLMODE_IAT)

  ' DeleteObject(hBitmap)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HBITMAP, 64)
  ff = opCall(IAT_DELETEOBJECT, CALLMODE_IAT)

  ' DeleteDC(memDC)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_MEMDC, 64)
  ff = opCall(IAT_DELETEDC, CALLMODE_IAT)

  '''' EndPaint
  ' lea rdx, [rsp+WNDPROC_SLOT_PAINTSTRUCT]
  ff = opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_PAINTSTRUCT, 64)
  ' mov rcx, [rsp+WNDPROC_SLOT_HWND]
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RSP, stack.WNDPROC_SLOT_HWND, 64)
  ' call EndPaint
  ff = opCall(IAT_ENDPAINT, CALLMODE_IAT)

  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)

  ' add rsp, GFX_WNDPROC_FRAME
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_WNDPROC_FRAME, 64)

  ' ret
  opRet

  ' .onKeyDown:
  onKeyDownTarget = emitPos

  ' Check if arrow keys (37-40)
  ' r8 is wParam
  ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 37, 32)
  jmpNotLeft = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 52, 32)
  jmpMapDone1 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  patch8 jmpNotLeft

  ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 38, 32)
  jmpNotUp = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 56, 32)
  jmpMapDone2 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  patch8 jmpNotUp

  ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 39, 32)
  jmpNotRight = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 54, 32)
  jmpMapDone3 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  patch8 jmpNotRight

  ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 40, 32)
  jmpNotDown = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 50, 32)
  jmpMapDone4 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
  patch8 jmpNotDown

  ' jmp .onDefault
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, onDefaultTarget, JCC_TYPE_NEAR)

  patch8 jmpMapDone1
  patch8 jmpMapDone2
  patch8 jmpMapDone3
  patch8 jmpMapDone4

  ' Fall through to .onChar:
  onCharTarget = emitPos

  ' Check if buffer is full: Head + 1 == Tail (modulo 256)
  ' lea rax, [rip + KbdHeadBase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -5, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov r10d, [rax]
  ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG, 0, 32)

  ' mov r11d, r10d
  ff = opMov(OP_TYPE_REG, 11, OP_TYPE_REG, 10, 32)

  ' inc r11d
  opIncReg 11, 32

  ' and r11d, 255
  ff = opALU(ALU_AND, OP_TYPE_REG, 11, OP_TYPE_IMM, 255, 32)

  ' lea rdx, [rip + KbdTailBase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64), -6, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' cmp r11d, [rdx]
  ff = opALU(ALU_CMP, OP_TYPE_REG, 11, OP_TYPE_MEM_REG, 2, 32)

  ' je .onCharEnd (buffer full)
  jmpOnCharEndPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' Store character at Head
  ' lea rcx, [rip + KbdBufBase]
  addPatch PATCH_GFX, opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64), -7, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' R8 holds the character (wParam)
  ' mov [rcx + r10], r8b
  ff = opMov_SIB(1, OP_TYPE_REG, 8, 1, 10, 1, 0, 8)

  ' Update Head
  ' mov [rax], r11d
  ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_REG, 11, 32)

  ' .onCharEnd:
  patch8 jmpOnCharEndPos

  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
  ' add rsp, GFX_WNDPROC_FRAME
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, stack.GFX_WNDPROC_FRAME, 64)
  ' ret
  opRet

  ' Patch displacements
  patch32 leaClassName1Pos, classNameRVA - (PE_TEXT_VA + leaClassName1Pos + 4)
  patch32 leaClassName2Pos, classNameRVA - (PE_TEXT_VA + leaClassName2Pos + 4)
  patch32 leaWindowNamePos, windowNameRVA - (PE_TEXT_VA + leaWindowNamePos + 4)
  patch32 leaPaletteFbPos, paletteRVA - (PE_TEXT_VA + leaPaletteFbPos + 4)
  patch32 leaFontFaceTerminalPos, fontFaceTerminalRVA - (PE_TEXT_VA + leaFontFaceTerminalPos + 4)
  patch32 leaWndProcPos, wndProcRVA - (PE_TEXT_VA + leaWndProcPos + 4)
  patch32 jmpOnDestroyPos, onDestroyTarget - (jmpOnDestroyPos + 4)
  patch32 jmpOnPaintPos, onPaintTarget - (jmpOnPaintPos + 4)
  patch32 jmpOnCharPos, onCharTarget - (jmpOnCharPos + 4)
  patch32 jmpOnKeyDownPos, onKeyDownTarget - (jmpOnKeyDownPos + 4)

  ' Patch UserCodeEntry
  patch32 leaUserCodePos, emitPos - (leaUserCodePos + 4)

END SUB ' emitPrologueWindowSetup

''''''''''''''''''''''''
''''''''''''''''''''''''
SUB emitRuntime

  '''' String Assignment Runtime Helper
  ' Inputs: RCX = LHS Descriptor Ptr, RDX = RHS Descriptor Ptr
  rt.StrAssignOffset = emitPos

  stack.currentStackOffset = 8
  ff = updateStackAlignment

  ' Check if LHS == RHS (e.g. A$ = A$) to prevent freeing the data we are trying to copy
  ' cmp rcx, rdx
  ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
  ' je .fastRet
  jmpFastRet = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' Prologue - Align stack to 16 bytes and allocate 32 bytes for Win x64 shadow space
  ' push rbp
  opPushReg 5
  ' mov rbp, rsp
  ff = opMov(OP_TYPE_REG, 5, OP_TYPE_REG, 4, 64)

  opPushReg 12
  opPushReg 13
  opPushReg 14
  opPushReg 15

  ' sub rsp, 32
  opSubRsp32 32

  ' mov r12, rcx
  ff = opMov(OP_TYPE_REG, 12, OP_TYPE_REG, 1, 64)
  ' mov r13, rdx
  ff = opMov(OP_TYPE_REG, 13, OP_TYPE_REG, 2, 64)

  ' Check if LHS needs freeing (Flags == 1)
  ' mov r8, [r12 + 16]
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG_DISP8, 12 + (16 * 256), 64)
  ' cmp r8, 1
  ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 64)
  ' jne .skipFree
  jmpSkipFree = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' Check if LHS Data Pointer is null
  ' mov r8, [r12]
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 12, 64)
  ' test r8, r8
  ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
  ' jz .skipFree
  jmpSkipFree2 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' Call HeapFree(hHeap, 0, r8)
  ' mov rcx, [rip + !PROCESS_HEAP_PTR]
  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' xor edx, edx
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
  ' call IAT_HEAPFREE
  ff = opCall(IAT_HEAPFREE, CALLMODE_IAT)

  ' .skipFree:
  patch32 jmpSkipFree, emitPos - (jmpSkipFree + 4)
  patch32 jmpSkipFree2, emitPos - (jmpSkipFree2 + 4)

  ' Check RHS length
  ff = genLoadStringDesc(13, 14, 15)

  ' test r15, r15
  ff = opTest(OP_TYPE_REG, 15, OP_TYPE_REG, 15, 64)
  ' jg .doAlloc
  jmpDoAlloc = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' If length is 0, zero LHS Descriptor and exit early
  ' xor eax, eax
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
  ' mov [r12], rax
  ff = opMov(OP_TYPE_MEM_REG, 12, OP_TYPE_REG, 0, 64)
  ' mov [r12 + 8], rax
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 12 + (8 * 256), OP_TYPE_REG, 0, 64)
  ' mov [r12 + 16], rax
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 12 + (16 * 256), OP_TYPE_REG, 0, 64)
  ' jmp .epilogue
  jmpEpi2 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  ' .doAlloc:
  patch32 jmpDoAlloc, emitPos - (jmpDoAlloc + 4)

  ' Call HeapAlloc(hHeap, 0, length + 1)
  ' mov r8, r15
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 15, 64)
  ' inc r8
  opIncReg 8, 64
  ' mov rcx, [rip + !PROCESS_HEAP_PTR]
  ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' xor edx, edx
  ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
  ' call IAT_HEAPALLOC
  ff = opCall(IAT_HEAPALLOC, CALLMODE_IAT)

  ' Update LHS Desc
  ' mov [r12], rax
  ff = opMov(OP_TYPE_MEM_REG, 12, OP_TYPE_REG, 0, 64)
  ' mov [r12 + 8], r15
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 12 + (8 * 256), OP_TYPE_REG, 15, 64)
  ' mov qword [r12 + 16], 1 (Flags = Dynamic)
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 12 + (16 * 256), OP_TYPE_IMM, 1, 64)

  ' Copy Data
  genBlockTransfer 14, 0, 15

  ' Write null terminator at the end of the newly copied string data
  ' mov byte [rdi], 0
  ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_IMM, 0, 8)

  ' .epilogue:
  patch32 jmpEpi2, emitPos - (jmpEpi2 + 4)

  ' add rsp, 32
  opAddRsp32 32

  opPopReg 15
  opPopReg 14
  opPopReg 13
  opPopReg 12

  ' pop rbp
  opPopReg 5

  stack.currentStackOffset = 0
  ff = updateStackAlignment

  ' .fastRet:
  patch32 jmpFastRet, emitPos - (jmpFastRet + 4)

  stack.currentStackOffset = 0
  ff = updateStackAlignment

  opRet

  '''' RT_PLOT_PIXEL
  rt.PlotPixelOffset = emitPos

  stack.currentStackOffset = 8
  ff = updateStackAlignment

  ' Preserve RBX since TIRA math backend uses it for RHS operands
  opPushReg 3

  ' Capture incoming ABI hardware registers into TIRA accessible global memory slots
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 1, 64, resolveSymbol("!RT_ARG1"))
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 2, 64, resolveSymbol("!RT_ARG2"))
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 8, 64, resolveSymbol("!RT_ARG3"))

  tiraStart

  endLbl$ = tiraLabelNew$("PLOT_END")

  ' Bounds check X
  tiraJmpCond "JL", "!RT_ARG1", "0", endLbl$
  tiraJmpCond "JGE", "!RT_ARG1", cTrNum$(gfxConfig.SizeX), endLbl$

  ' Bounds check Y
  tiraJmpCond "JL", "!RT_ARG2", "0", endLbl$
  tiraJmpCond "JGE", "!RT_ARG2", cTrNum$(gfxConfig.SizeY), endLbl$

  ' Calculate offset
  tiraOp TC_MUL, "!RT_PLOT_OFFSET", "!RT_ARG2", cTrNum$(gfxConfig.SizeX)
  tiraOp TC_ADD, "!RT_PLOT_OFFSET", "!RT_PLOT_OFFSET", "!RT_ARG1"

  ' Fetch framebuffer base pointer
  tiraNew TC_FRAMEBUF_PTR, "!RT_PLOT_FBBASE"

  ' Target address
  tiraOp TC_ADD, "!RT_PLOT_TARGET", "!RT_PLOT_FBBASE", "!RT_PLOT_OFFSET"

  ' Write byte to framebuffer
  tiraWriteMem "!RT_PLOT_TARGET", "!RT_ARG3", "1"

  tiraLabel endLbl$

  tiraEndAndProcess

  opPopReg 3

  stack.currentStackOffset = 0
  ff = updateStackAlignment

  opRet

  '''' RT_LINE
  rt.LineOffset = emitPos

  ' Ensure TIRA accurately tracks the physical stack alignment
  ' A standard Windows x64 function call leaves RSP misaligned by 8 bytes (the return address)
  stack.currentStackOffset = 8

  ' Preserve RBX since TIRA math backend uses it for RHS operands
  opPushReg 3

  ' Capture incoming ABI hardware registers into TIRA accessible global memory slots
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 1, 64, resolveSymbol("!RT_X1"))
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 2, 64, resolveSymbol("!RT_Y1"))
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 8, 64, resolveSymbol("!RT_X2"))
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 9, 64, resolveSymbol("!RT_Y2"))

  ' Capture Stack arguments (Accounting for the 8 byte return address and 8 byte RBX push = +16 relative to caller's RSP)
  ' Because RT calls no longer reserve 32 bytes of shadow space, the offset math is much leaner
  ' Caller pushed 0 bytes shadow + 24 bytes args (padded to 32 bytes to maintain 16-byte stack alignment).
  ' Arg 5 (Color) is at [caller RSP + 0]. Relative to current RSP: 0 + 16 = 16.
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, 16, 64)
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, resolveSymbol("!RT_COLOR"))

  ' Arg 6 (BoxType) is at [caller RSP + 8]. Relative to current RSP: 8 + 16 = 24.
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, 24, 64)
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, resolveSymbol("!RT_BOX"))

  ' Arg 7 (Style) is at [caller RSP + 16]. Relative to current RSP: 16 + 16 = 32.
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RSP, 32, 64)
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, resolveSymbol("!RT_STYLE"))

  tiraStart

  lblNotBF$ = tiraLabelNew$("NOT_BF")
  lblEndBF$ = tiraLabelNew$("END_BF")

  ' IF !RT_BOX != 2 GOTO NOT_BF
  tiraJmpCond "JNE", "!RT_BOX", "2", lblNotBF$

  ' Swap X if X1 > X2
  lblSkipSwapX_BF$ = tiraLabelNew$("SKIP_SWAP_X_BF")
  tiraJmpCond "JLE", "!RT_X1", "!RT_X2", lblSkipSwapX_BF$
  tiraAssign "!RT_TMPX", "!RT_X1"
  tiraAssign "!RT_X1", "!RT_X2"
  tiraAssign "!RT_X2", "!RT_TMPX"
  tiraLabel lblSkipSwapX_BF$

  ' Swap Y if Y1 > Y2
  lblSkipSwapY_BF$ = tiraLabelNew$("SKIP_SWAP_Y_BF")
  tiraJmpCond "JLE", "!RT_Y1", "!RT_Y2", lblSkipSwapY_BF$
  tiraAssign "!RT_TMPY", "!RT_Y1"
  tiraAssign "!RT_Y1", "!RT_Y2"
  tiraAssign "!RT_Y2", "!RT_TMPY"
  tiraLabel lblSkipSwapY_BF$

  ' Outer Loop (Y)
  tiraAssign "!RT_TMPY", "!RT_Y1"
  lblLoopY_BF$ = tiraLabelNew$("LOOP_Y_BF")
  tiraLabel lblLoopY_BF$
  tiraJmpCond "JG", "!RT_TMPY", "!RT_Y2", lblEndBF$

  ' Inner Loop (X)
  tiraAssign "!RT_TMPX", "!RT_X1"
  lblLoopX_BF$ = tiraLabelNew$("LOOP_X_BF")
  lblEndX_BF$ = tiraLabelNew$("END_X_BF")
  tiraLabel lblLoopX_BF$
  tiraJmpCond "JG", "!RT_TMPX", "!RT_X2", lblEndX_BF$

  tiraCall "RT_PLOT_PIXEL", 3, "!RT_TMPX, !RT_TMPY, !RT_COLOR"

  tiraOp TC_ADD, "!RT_TMPX", "!RT_TMPX", "1"
  tiraJmp lblLoopX_BF$
  tiraLabel lblEndX_BF$

  tiraOp TC_ADD, "!RT_TMPY", "!RT_TMPY", "1"
  tiraJmp lblLoopY_BF$

  tiraLabel lblEndBF$
  lblEndLine$ = tiraLabelNew$("END_LINE")
  tiraJmp lblEndLine$

  tiraLabel lblNotBF$

  ' Box (B) Logic
  lblNotB$ = tiraLabelNew$("NOT_B")
  tiraJmpCond "JNE", "!RT_BOX", "1", lblNotB$

  ' Swap X if X1 > X2
  lblSkipSwapX_B$ = tiraLabelNew$("SKIP_SWAP_X_B")
  tiraJmpCond "JLE", "!RT_X1", "!RT_X2", lblSkipSwapX_B$
  tiraAssign "!RT_TMPX", "!RT_X1"
  tiraAssign "!RT_X1", "!RT_X2"
  tiraAssign "!RT_X2", "!RT_TMPX"
  tiraLabel lblSkipSwapX_B$

  ' Swap Y if Y1 > Y2
  lblSkipSwapY_B$ = tiraLabelNew$("SKIP_SWAP_Y_B")
  tiraJmpCond "JLE", "!RT_Y1", "!RT_Y2", lblSkipSwapY_B$
  tiraAssign "!RT_TMPY", "!RT_Y1"
  tiraAssign "!RT_Y1", "!RT_Y2"
  tiraAssign "!RT_Y2", "!RT_TMPY"
  tiraLabel lblSkipSwapY_B$

  ' H1: Y=Y1, X=X1 to X2
  tiraAssign "!RT_TMPX", "!RT_X1"
  lblLoopH1$ = tiraLabelNew$("LOOP_H1")
  lblEndH1$ = tiraLabelNew$("END_H1")
  tiraLabel lblLoopH1$
  tiraJmpCond "JG", "!RT_TMPX", "!RT_X2", lblEndH1$
  tiraBuildStylePlot "!RT_TMPX", "!RT_Y1"
  tiraOp TC_ADD, "!RT_TMPX", "!RT_TMPX", "1"
  tiraJmp lblLoopH1$
  tiraLabel lblEndH1$

  ' H2: Y=Y2, X=X1 to X2
  tiraAssign "!RT_TMPX", "!RT_X1"
  lblLoopH2$ = tiraLabelNew$("LOOP_H2")
  lblEndH2$ = tiraLabelNew$("END_H2")
  tiraLabel lblLoopH2$
  tiraJmpCond "JG", "!RT_TMPX", "!RT_X2", lblEndH2$
  tiraBuildStylePlot "!RT_TMPX", "!RT_Y2"
  tiraOp TC_ADD, "!RT_TMPX", "!RT_TMPX", "1"
  tiraJmp lblLoopH2$
  tiraLabel lblEndH2$

  ' V1: X=X1, Y=Y1 to Y2
  tiraAssign "!RT_TMPY", "!RT_Y1"
  lblLoopV1$ = tiraLabelNew$("LOOP_V1")
  lblEndV1$ = tiraLabelNew$("END_V1")
  tiraLabel lblLoopV1$
  tiraJmpCond "JG", "!RT_TMPY", "!RT_Y2", lblEndV1$
  tiraBuildStylePlot "!RT_X1", "!RT_TMPY"
  tiraOp TC_ADD, "!RT_TMPY", "!RT_TMPY", "1"
  tiraJmp lblLoopV1$
  tiraLabel lblEndV1$

  ' V2: X=X2, Y=Y1 to Y2
  tiraAssign "!RT_TMPY", "!RT_Y1"
  lblLoopV2$ = tiraLabelNew$("LOOP_V2")
  lblEndV2$ = tiraLabelNew$("END_V2")
  tiraLabel lblLoopV2$
  tiraJmpCond "JG", "!RT_TMPY", "!RT_Y2", lblEndV2$
  tiraBuildStylePlot "!RT_X2", "!RT_TMPY"
  tiraOp TC_ADD, "!RT_TMPY", "!RT_TMPY", "1"
  tiraJmp lblLoopV2$
  tiraLabel lblEndV2$

  tiraJmp lblEndLine$
  tiraLabel lblNotB$

  ' Bresenham Line Logic
  ' dx
  tiraOp TC_SUB, "!RT_DX", "!RT_X2", "!RT_X1"
  lblSkipNegDX$ = tiraLabelNew$("SKIP_NEG_DX")
  tiraAssign "!RT_SX", "1"
  tiraJmpCond "JGE", "!RT_DX", "0", lblSkipNegDX$
  tiraOp TC_NEG, "!RT_DX", "!RT_DX", ""
  tiraAssign "!RT_SX", "-1"
  tiraLabel lblSkipNegDX$

  ' dy
  tiraOp TC_SUB, "!RT_DY", "!RT_Y2", "!RT_Y1"
  lblSkipNegDY$ = tiraLabelNew$("SKIP_NEG_DY")
  tiraAssign "!RT_SY", "1"
  tiraJmpCond "JGE", "!RT_DY", "0", lblSkipNegDY$
  tiraOp TC_NEG, "!RT_DY", "!RT_DY", ""
  tiraAssign "!RT_SY", "-1"
  tiraLabel lblSkipNegDY$
  tiraOp TC_NEG, "!RT_DY", "!RT_DY", ""

  ' err = dx + dy
  tiraOp TC_ADD, "!RT_ERR", "!RT_DX", "!RT_DY"

  lblLoopLine$ = tiraLabelNew$("LOOP_LINE")
  tiraLabel lblLoopLine$

  ' Plot
  tiraBuildStylePlot "!RT_X1", "!RT_Y1"

  ' Check break
  lblNotDone$ = tiraLabelNew$("NOT_DONE")
  tiraJmpCond "JNE", "!RT_X1", "!RT_X2", lblNotDone$
  tiraJmpCond "JE", "!RT_Y1", "!RT_Y2", lblEndLine$
  tiraLabel lblNotDone$

  ' e2 = err * 2
  tiraOp TC_MUL, "!RT_E2", "!RT_ERR", "2"

  ' if e2 >= dy
  lblSkipDX$ = tiraLabelNew$("SKIP_DX")
  tiraJmpCond "JL", "!RT_E2", "!RT_DY", lblSkipDX$
  tiraOp TC_ADD, "!RT_ERR", "!RT_ERR", "!RT_DY"
  tiraOp TC_ADD, "!RT_X1", "!RT_X1", "!RT_SX"
  tiraLabel lblSkipDX$

  ' if e2 <= dx
  lblSkipDY$ = tiraLabelNew$("SKIP_DY")
  tiraJmpCond "JG", "!RT_E2", "!RT_DX", lblSkipDY$
  tiraOp TC_ADD, "!RT_ERR", "!RT_ERR", "!RT_DX"
  tiraOp TC_ADD, "!RT_Y1", "!RT_Y1", "!RT_SY"
  tiraLabel lblSkipDY$

  tiraJmp lblLoopLine$

  tiraLabel lblEndLine$

  tiraEndAndProcess

  opPopReg 3

  ' Safely revert the manual stack alignment tracking adjustment
  stack.currentStackOffset = 0
  ff = updateStackAlignment

  opRet

  '''' RT_VEH_HANDLER
  rt.VehHandlerOffset = emitPos

  ' Read ExceptionCode from structure
  ' mov rax, [rcx] (ExceptionRecord pointer)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 1, 64)
  ' mov eax, [rax] (ExceptionCode)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 0, 32)

  ' Check for Integer Divide by Zero (0xC0000094)
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, &HC0000094, 32)
  jmpIsMatch1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' Check for Float Divide by Zero (0xC000008E)
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_IMM, &HC000008E, 32)
  jmpIsMatch2 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' Not a recognized exception, gracefully pass it back to Windows
  ' Return EXCEPTION_CONTINUE_SEARCH (0) in RAX
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
  opRet

  ' Valid Exception Matched
  patch8 jmpIsMatch1
  patch8 jmpIsMatch2

  ' Check if the user has an ON ERROR GOTO handler set
  ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64, internalErrHandlerSymbolIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' test rdx, rdx
  ff = opTest(OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)
  jmpHasHandler = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' No user handler found, return EXCEPTION_CONTINUE_SEARCH (0)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
  opRet

  ' .hasHandler
  patch8 jmpHasHandler

  ' Start modifying the CPU CONTEXT struct to safely route execution into our basic program space
  ' mov r8, [rcx + 8] (Context Pointer)
  ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG_DISP8, 1 + (8 * 256), 64)

  ' Navigate to Context.Rsp to reset the dirty execution stack
  ' add r8, 152
  ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_IMM, 152, 64)

  ' Retrieve the pristine, clean !SAFE_RSP we recorded during prologue
  ff = genSymbolRouteMov(OP_TYPE_REG, 9, OP_TYPE_MEM_RIP, 0, 64, internalSafeRspSymbolIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' Write it into Context.Rsp
  ' mov [r8], r9
  ff = opMov(OP_TYPE_MEM_REG, 8, OP_TYPE_REG, 9, 64)

  ' Write it into Context.Rbp to pull the base pointer out of any deep subroutine frames
  ' mov [r8 + 8], r9
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 8 + (8 * 256), OP_TYPE_REG, 9, 64)

  ' Redirect the Instruction Pointer (RIP)
  ' add r8, 96 (152 + 96 = 248, RIP Offset)
  ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_IMM, 96, 64)

  ' First save the crashing instruction's address for the RESUME keyword
  ' mov r10, [r8]
  ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG, 8, 64)
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 10, 64, internalLastErrRipSymbolIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' Write the user's error label address into Context.Rip
  ' mov [r8], rdx
  ff = opMov(OP_TYPE_MEM_REG, 8, OP_TYPE_REG, 2, 64)

  ' Return EXCEPTION_CONTINUE_EXECUTION (-1) so Windows allows the thread to seamlessly continue
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, -1, 64)
  opRet

  '''' RT_KEYDOWN
  ' Bypass data table payload manually deposited into the code section
  jmpSkipTable = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

  tableStart = emitPos
  FOR ii = 0 TO keyMappingCount - 1
    emitBytes32 keyMapping(ii).qbCode
    emitBytes32 keyMapping(ii).vkCode
  NEXT

  patch32 jmpSkipTable, emitPos - (jmpSkipTable + 4)

  rt.KeyDownOffset = emitPos

  stack.currentStackOffset = 8
  ff = updateStackAlignment

  ' Save non-volatile registers
  opPushReg 13
  opPushReg 14
  opPushReg 15

  ' RCX arrives loaded with the requested key code
  ' R15 = Key Code to check
  ff = opMov(OP_TYPE_REG, 15, OP_TYPE_REG, 1, 64)

  ' R13 = Number of mappings
  ff = opMov(OP_TYPE_REG, 13, OP_TYPE_IMM, keyMappingCount, 64)

  ' R14 = Address of the mapping table using a custom relative layout jump
  leaTablePos = opLea(OP_TYPE_REG, 14, OP_TYPE_MEM_RIP, 0, 64)
  patch32 leaTablePos, tableStart - (leaTablePos + 4)

  loopScanStart = emitPos

  ' If mapped items remain = 0, we're done (not found in table)
  ff = opTest(OP_TYPE_REG, 13, OP_TYPE_REG, 13, 64)
  jmpDoneScan1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' Compare table[index].qbCode (R14) with R15
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 14, 32)
  ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 15, 32)
  jmpFound = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' Advance to next 8-byte entry (qbCode + vkCode layout)
  ff = opALU(ALU_ADD, OP_TYPE_REG, 14, OP_TYPE_IMM, 8, 64)
  opDecReg 13, 64
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, loopScanStart, JCC_TYPE_SHORT)

  ' Match found, extract table[index].vkCode to R15
  patch8 jmpFound
  ff = opMov(OP_TYPE_REG, 15, OP_TYPE_MEM_REG_DISP8, 14 + (4 * 256), 32)

  patch8 jmpDoneScan1

  ' Setup GetAsyncKeyState
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)

  ff = genAlignedCall(IAT_GETASYNCKEYSTATE, 13, DEFAULT)

  ' Check MSB
  ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)
  jmpIsDown = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ' Not down (return 0)
  ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
  jmpEnd = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  patch8 jmpIsDown
  ' Is down (return -1)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, -1, 64)

  patch8 jmpEnd

  opPopReg 15
  opPopReg 14
  opPopReg 13

  stack.currentStackOffset = 0
  ff = updateStackAlignment

  opRet

END SUB ' emitRuntime

''''''''''''''''''''''''
SUB emitSubEpilogue

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM totalFrame AS LONG
  DIM dt AS LONG
  DIM uIdx AS LONG
  DIM fOffset AS LONG
  DIM rbpOffset AS LONG

  ' GC sweep start
  IF insideSub > 0 AND currentScopeID > 0 THEN
    FOR vIdx = 0 TO symbolCount - 1
      IF symbols(vIdx).ScopeID = currentScopeID AND symbols(vIdx).IsLocal = 1 THEN
        IF symbols(vIdx).IsArray = 2 THEN
          emitDeepFreeArray vIdx
        ELSE
          dt = symbols(vIdx).DataType

          subIdx = -1
          FOR iSub = 0 TO subCount - 1
            IF subs(iSub).ScopeID = currentScopeID THEN subIdx = iSub: EXIT FOR
          NEXT

          IF subIdx <> -1 THEN
            rbpOffset = symbols(vIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56

            IF dt = TYPE_STRING THEN
              ' Local Scalar String: 24-byte inline descriptor on stack
              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RBP, rbpOffset + 16, 64) ' flags
              ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 64)
              jmpSkipFlag = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RBP, rbpOffset, 64) ' data ptr
              ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
              jmpSkipPtr = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

              ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
              ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
              ff = genAlignedCall(IAT_HEAPFREE, 15, DEFAULT)

              patch8 jmpSkipFlag
              patch8 jmpSkipPtr

            ELSE
              IF dt = TYPE_UDT THEN
                ' Local Scalar UDT: Free dynamic strings stored within
                uIdx = symbols(vIdx).UDTIndex
                FOR f = 0 TO udts(uIdx).FieldCount - 1
                  IF udtFields(uIdx, f).DataType = TYPE_STRING AND udtFields(uIdx, f).UDTIndex = 1 THEN
                    fOffset = rbpOffset + udtFields(uIdx, f).Offset

                    ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RBP, fOffset, 64)
                    ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
                    jmpSkipF = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

                    opPushReg 1
                    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG_DISP8, 1 + (16 * 256), 64)
                    ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 64)
                    jmpSkipD = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

                    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 1, 64)
                    ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
                    jmpSkipD2 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

                    ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
                    ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
                    ff = genAlignedCall(IAT_HEAPFREE, 15, DEFAULT)

                    patch8 jmpSkipD
                    patch8 jmpSkipD2
                    opPopReg 8

                    ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
                    ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
                    ff = genAlignedCall(IAT_HEAPFREE, 15, DEFAULT)

                    patch8 jmpSkipF
                  END IF
                NEXT
              END IF
            END IF
          END IF
        END IF
      END IF
    NEXT
  END IF
  ' GC sweep end

  totalFrame = stack.consoleFrameSize

  IF currentSubName$ <> "" THEN
    vIdx = resolveSymbol(currentSubName$)
    IF vIdx <> -1 THEN
      subIdx = symbols(vIdx).SubIndex
      IF subIdx <> -1 THEN
        totalFrame = totalFrame + subs(subIdx).LocalFrameSize
      END IF
    END IF
  END IF

  ' Deallocate the local stack frame
  ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, totalFrame, 64)

  ' Pop non-volatile registers in reverse order to conform to x64 ABI
  opPopReg 15 ' R15
  opPopReg 14 ' R14
  opPopReg 13 ' R13
  opPopReg 12 ' R12
  opPopReg 7 ' RDI
  opPopReg 6 ' RSI
  opPopReg 3 ' RBX

  ' Restore caller's RBP frame pointer
  opPopReg 5 ' RBP

  ' Return to caller
  opRet

END SUB ' emitSubEpilogue

''''''''''''''''''''''''
SUB emitSubPrologue

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM totalFrame AS LONG
  DIM zeroLoopStart AS LONG
  DIM jmpZeroEnd AS LONG

  ' Standard x64 ABI Prologue: Set up RBP as a stable frame pointer
  opPushReg 5 ' RBP
  ff = opMov(OP_TYPE_REG, 5, OP_TYPE_REG, 4, 64) ' mov rbp, rsp

  ' Push non-volatile registers to conform to x64 ABI calling conventions.
  ' We push exactly 7 more registers to reach 8 total (64 bytes), maintaining
  ' the strict 16-byte stack alignment offset required before allocating the local frame.
  opPushReg 3 ' RBX
  opPushReg 6 ' RSI
  opPushReg 7 ' RDI
  opPushReg 12 ' R12
  opPushReg 13 ' R13
  opPushReg 14 ' R14
  opPushReg 15 ' R15

  totalFrame = stack.consoleFrameSize

  IF currentSubName$ <> "" THEN
    vIdx = resolveSymbol(currentSubName$)
    IF vIdx <> -1 THEN
      subIdx = symbols(vIdx).SubIndex
      IF subIdx <> -1 THEN
        subs(subIdx).ExitPatchList = 0 ' Initialize the Exit Patch List
        totalFrame = totalFrame + subs(subIdx).LocalFrameSize
      END IF
    END IF
  END IF

  ' Allocate the local stack frame
  ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, totalFrame, 64)

  ' Zero out the newly allocated stack frame to prevent garbage data from crashing
  ' Use volatile registers: R8=0, RCX=totalFrame, RAX=RSP
  ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
  ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, totalFrame, 64)
  ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 4, 64)

  zeroLoopStart = emitPos
  ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
  jmpZeroEnd = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

  ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_REG, 8, 64)
  ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_IMM, 8, 64)
  ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_IMM, 8, 64)
  ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, zeroLoopStart, JCC_TYPE_SHORT)

  patch8 jmpZeroEnd

END SUB ' emitSubPrologue

''''''''''''''''''''''''
FUNCTION evalMathConst$ (wExpr$)

  DIM pDepth AS LONG
  DIM pStart AS LONG
  DIM pEnd AS LONG
  DIM ix AS LONG
  DIM eLen AS LONG

  IF LEFT$(wExpr$, 1) = CHR$(34) THEN
    evalMathConst$ = wExpr$
    EXIT FUNCTION
  END IF

  ' Pass 0: Resolve parentheses recursively
  pDepth = 0
  pStart = 0
  pEnd = 0
  eLen = LEN(wExpr$)

  FOR ix = 1 TO eLen
    ch$ = MID$(wExpr$, ix, 1)
    IF ch$ = "(" THEN
      IF pDepth = 0 THEN pStart = ix
      pDepth = pDepth + 1
    ELSE
      IF ch$ = ")" THEN
        pDepth = pDepth - 1
        IF pDepth = 0 THEN
          pEnd = ix
          EXIT FOR
        END IF
      END IF
    END IF
  NEXT

  IF pStart > 0 THEN
    IF pEnd > pStart THEN
      innerStr$ = MID$(wExpr$, pStart + 1, pEnd - pStart - 1)
      evalInner$ = evalMathConst$(innerStr$)
      newExpr$ = LEFT$(wExpr$, pStart - 1) + evalInner$ + MID$(wExpr$, pEnd + 1)
      evalMathConst$ = evalMathConst$(newExpr$)
      EXIT FUNCTION
    ELSE
      ' Mismatched parenthesis safety fallback
      evalMathConst$ = wExpr$
      EXIT FUNCTION
    END IF
  END IF

  DIM tTokens$(64)
  DIM tCount AS LONG
  tCount = 0

  ix = 1
  DO WHILE ix <= eLen
    ch$ = MID$(wExpr$, ix, 1)
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
            c2$ = MID$(wExpr$, ix, 1)
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
            c2$ = MID$(wExpr$, ix, 1)
            IF (c2$ >= "0" AND c2$ <= "9") OR c2$ = "." THEN
              num$ = num$ + c2$
              ix = ix + 1
            ELSE
              IF c2$ = "&" AND num$ = "" AND ix < eLen THEN
                IF UCASE$(MID$(wExpr$, ix + 1, 1)) = "H" THEN
                  num$ = "&H"
                  ix = ix + 2
                  DO WHILE ix <= eLen
                    c3$ = UCASE$(MID$(wExpr$, ix, 1))
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
            tTokens$(tCount) = MID$(wExpr$, ix, 1)
            tCount = tCount + 1
            ix = ix + 1
          END IF
        END IF
      END IF
    END IF
  LOOP

  IF tCount = 0 THEN
    evalMathConst$ = wExpr$
    EXIT FUNCTION
  END IF

  DIM nTokens$(64)
  DIM nCount AS LONG

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

  evalMathConst$ = nTokens$(0)

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

  rwvar$ = " " ' Necessary
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

  rwVar$ = " " ' Necessary
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

  rwVar$ = " " ' Necessary

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
SUB fileOpenModal

  DIM fileList$(1000)
  DIM fileCount AS LONG
  DIM localScrollY AS LONG

  ' Get directory listing safely
  SHELL _HIDE "cmd /c dir /b /a-d *.txt > flist.tmp"

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
    addStatusMsg "NO TXT FILES FOUND"
    EXIT SUB
  END IF

  localScrollY = 0

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
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, -1

    IF mouse.Released1 THEN
      IF mouseWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) AND mouseDownWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
        EXIT DO
      END IF
    END IF

    PrintStr boxX + (boxW \ 2) - (9 * 4), boxY + 3, "OPEN FILE", 14, -1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    itemH = 10
    maxLines = (boxH - 15) \ itemH

    ' Scrollbar
    scrollBarX = boxX + boxW - 12
    scrollBarY = boxY + 14
    scrollBarW = 12
    scrollBarH = boxH - 15

    drawBorderBox scrollBarX, scrollBarY, scrollBarW, scrollBarH, 15, 0
    PrintChr scrollBarX + 2, scrollBarY + 1, CHR$(24), 15, -1
    PrintChr scrollBarX + 2, scrollBarY + scrollBarH - 9, CHR$(25), 15, -1

    IF fileCount > maxLines THEN
      scrollRange = fileCount - maxLines
      thumbH = scrollBarH - 20
      thumbMaxH = thumbH
      thumbSize = (maxLines * thumbMaxH) \ fileCount
      IF thumbSize < 8 THEN thumbSize = 8
      thumbY = scrollBarY + 10 + ((localScrollY * (thumbMaxH - thumbSize)) \ scrollRange)
      LINE (scrollBarX + 1, thumbY)-(scrollBarX + scrollBarW - 2, thumbY + thumbSize - 1), 15, BF
    ELSE
      LINE (scrollBarX + 1, scrollBarY + 10)-(scrollBarX + scrollBarW - 2, scrollBarY + scrollBarH - 11), 15, BF
    END IF

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

          IF mouse.Released1 AND mouseDownWithinBoxBounds(boxX + 2, itemY, boxW - 16, itemH) THEN
            LINE (boxX + 2, itemY)-(boxX + boxW - 15, itemY + itemH - 1), 1, BF
            PrintStr boxX + 8, itemY + 1, sOutName$, 15, -1

            _DISPLAY
            tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

            tempCodeName$ = fileNameCode$
            fileNameCode$ = fileList$(fIdx)
            fileCodeLoad
            fileNameCode$ = tempCodeName$

            editor.CursorY = 1
            editor.CursorX = 0
            editor.ScrollY = 1
            editor.ScrollX = 0
            editor.SelectStartX = 0
            editor.SelectStartY = 1
            editor.IsSelecting = 0
            editor.Focus = 1

            EXIT DO
          END IF
        END IF

        PrintStr boxX + 8, itemY + 1, sOutName$, 11, -1
      END IF
    NEXT

    _DISPLAY

    kVal = keyCheck("ESC")
    IF kVal = 27 THEN
      waitKeyRelease "ESC"
      EXIT DO
    END IF

    ' Handle scrollbar clicks
    IF mouse.Released1 THEN
      IF mouseWithinBoxBounds(scrollBarX, scrollBarY, scrollBarW, 10) THEN
        localScrollY = localScrollY - 1
        IF localScrollY < 0 THEN localScrollY = 0
      END IF
      IF mouseWithinBoxBounds(scrollBarX, scrollBarY + scrollBarH - 10, scrollBarW, 10) THEN
        localScrollY = localScrollY + 1
        maxScroll = fileCount - maxLines
        IF maxScroll < 0 THEN maxScroll = 0
        IF localScrollY > maxScroll THEN localScrollY = maxScroll
      END IF
    END IF

  LOOP

END SUB ' fileOpenModal

''''''''''''''''''''''''
SUB fileOutputErrorReport (wStr1$, wStr2$)

  rwVar$ = " " ' Necessary

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

  rwVar$ = CHR$(13): PUT #1, , rwVar$
  rwVar$ = CHR$(10): PUT #1, , rwVar$

  IF wStr2$ <> "" THEN
    FOR ix = 1 TO LEN(wStr2$)
      rwVar$ = MID$(wStr2$, ix, 1)
      PUT #1, , rwVar$
    NEXT
    rwVar$ = CHR$(13): PUT #1, , rwVar$
    rwVar$ = CHR$(10): PUT #1, , rwVar$
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

    waitTimeGoal = TIMER + 0.1
    DO WHILE TIMER < waitTimeGoal
    LOOP

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

  rwVar$ = " " ' Necessary, do not remove
  FOR ii = 0 TO outputFileIdx - 1
    rwVar$ = CHR$(outputFile(ii))
    PUT #1, , rwVar$
  NEXT

  CLOSE #1

END SUB ' fileSaveBinary

''''''''''''''''''''''''
SUB fileSaveModal

  DIM saveAsName$
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
    PrintStr boxX + (boxW \ 2) - 28, boxY + 3, "SAVE AS", 14, -1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    closeBtnW = 15
    closeBtnH = 13
    closeBtnX = boxX + boxW - closeBtnW
    closeBtnY = boxY
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, -1

    IF mouse.Released1 THEN
      IF mouseWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) AND mouseDownWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
        EXIT DO
      END IF
    END IF

    ' Input box
    inputBoxX = boxX + 16
    inputBoxY = boxY + 24
    inputBoxW = boxW - 32
    inputBoxH = 16
    drawBorderBox inputBoxX, inputBoxY, inputBoxW, inputBoxH, 15, 0

    ' Draw text
    PrintStr inputBoxX + 4, inputBoxY + 4, saveAsName$ + "_", 15, -1

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

END SUB ' fileSaveModal

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

  sPassEndInx = lineTokenCount - 1
  sPassNextIdx = -1

  parenDepth = 0
  FOR ii = startIdx TO lineTokenCount - 1
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
    IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1
    IF parenDepth = 0 THEN
      IF tVal = 256 + ASC(":") THEN
        sPassEndInx = ii - 1
        sPassNextIdx = ii + 1
        EXIT FOR
      END IF

      ' Prevent the tokenizer from swallowing chained statements like NEXT varName
      IF ii > startIdx THEN
        IF tVal = TOK_NEXT OR tVal = TOK_GOTO THEN
          sPassEndInx = ii - 1
          sPassNextIdx = ii
          EXIT FOR
        END IF
      END IF
    END IF
  NEXT

  return2 sPassNextIdx ' f2
  findInstructionEnd = sPassEndInx

END FUNCTION ' findInstructionEnd

''''''''''''''''''''''''
FUNCTION findMatchingParen (startIdx, endIdx)

  DIM pDepth AS LONG
  DIM ii AS LONG
  DIM tVal AS LONG
  DIM tempRet AS LONG

  tempRet = -1
  pDepth = 0

  FOR ii = startIdx TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN
      pDepth = pDepth - 1
      IF pDepth = 0 THEN
        tempRet = ii
        EXIT FOR
      END IF
    END IF
  NEXT

  findMatchingParen = tempRet

END FUNCTION ' findMatchingParen

''''''''''''''''''''''''
FUNCTION findNextTokenAtDepth0 (startIdx, endIdx, passTokVal)

  DIM pDepth AS LONG
  DIM ii AS LONG
  DIM tVal AS LONG
  DIM tempRet AS LONG

  tempRet = -1
  pDepth = 0

  FOR ii = startIdx TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND tVal = passTokVal THEN
      tempRet = ii
      EXIT FOR
    END IF
  NEXT

  findNextTokenAtDepth0 = tempRet

END FUNCTION ' findNextTokenAtDepth0

''''''''''''''''''''''''
FUNCTION findSymbol (vName$)

  DIM hVal AS LONG
  DIM checkIdx AS LONG
  DIM globalIdx AS LONG
  DIM searchName$
  DIM firstCh AS STRING * 1

  searchName$ = UCASE$(vName$)
  globalIdx = -1
  hVal = hashString(searchName$)
  checkIdx = symHash(hVal)
  firstCh = LEFT$(searchName$, 1)

  DO WHILE checkIdx <> -1
    IF RTRIM$(symbols(checkIdx).RecordName) = searchName$ THEN
      IF currentScopeID > 0 AND symbols(checkIdx).ScopeID = currentScopeID THEN
        findSymbol = checkIdx
        EXIT FUNCTION
      END IF
      IF symbols(checkIdx).ScopeID = 0 THEN
        IF currentScopeID = 0 THEN
          IF globalIdx = -1 THEN globalIdx = checkIdx
        ELSE
          IF symbols(checkIdx).IsShared = 1 OR symbols(checkIdx).SubIndex <> -1 OR firstCh = "!" OR firstCh = "&" THEN
            IF globalIdx = -1 THEN globalIdx = checkIdx
          END IF
        END IF
      END IF
    END IF
    checkIdx = symbols(checkIdx).HashNext
  LOOP

  findSymbol = globalIdx

END FUNCTION ' findSymbol

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

  ' Shadow Space Allocation - Carve out the mandatory bytes for the Windows API scratchpad
  opSubRsp32 allocSize

  ' The API Call - Now that the stack is perfectly formatted, safely execute the OS function
  ff = opCall(iatConst, CALLMODE_IAT)

  ' The Cleanup - Destroy the shadow space to restore the stack
  opAddRsp32 allocSize

  ' If we pushed a dummy register above to fix alignment, pop it back off to leave the stack exactly as we found it
  IF pushedFiller = 1 THEN
    opPopReg backupReg
  END IF

  genAlignedCall = 1

END FUNCTION ' genAlignedCall

''''''''''''''''''''''''
FUNCTION genAllocTempMemory (sizeType, sizeInfo, destReg)

  ' Load Temp Heap Pointer
  ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    genAllocTempMemory = 0
    EXIT FUNCTION
  END IF

  ' Subtract length to allocate backwards
  ff = opALU(ALU_SUB, OP_TYPE_REG, destReg, sizeType, sizeInfo, 64)

  ' Update Temp Heap Pointer
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, destReg, 64, TEMP_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    genAllocTempMemory = 0
    EXIT FUNCTION
  END IF

  genAllocTempMemory = 1

END FUNCTION ' genAllocTempMemory

''''''''''''''''''''''''
SUB genBlockTransfer (srcReg, destReg, lenReg)

  ' The gen prefix indicates a higher-level code generation helper used to reduce boilerplate

  ' Emits an x64 block copy by transferring data from a source address register to a
  ' destination address register for a specified length. This helper automatically
  ' manages architectural register assignment and provides a safety check to skip
  ' the operation if the length is zero

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

END SUB ' genBlockTransfer

''''''''''''''''''''''''
FUNCTION genCastExprToInt (useTruncate)

  DIM opMode AS LONG

  IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
    opMode = MODE_SSE_DOUBLE
    IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE

    IF useTruncate = 1 THEN
      ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
    ELSE
      ' Standard CVTSD2SI performs rounding based on MXCSR register (default nearest)
      ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
    END IF

    exprIs.DataType = TYPE_LONG
  END IF

  genCastExprToInt = 1

END FUNCTION ' genCastExprToInt

''''''''''''''''''''''''
FUNCTION genForceNumericInt (passStartIdx, passEndIdx, passErrMsg$)

  ' This wrapper passes 1 (True) to automatically allow implicit variables
  ' for command arguments like LINE, LOCATE, and COLOR.
  genForceNumericInt = genForceNumericIntEx(passStartIdx, passEndIdx, 1, passErrMsg$)

END FUNCTION ' genForceNumericInt

''''''''''''''''''''''''
FUNCTION genForceNumericIntEx (passStartIdx, passEndIdx, allowImplicit, passErrMsg$)

  DIM opMode AS LONG
  DIM exprRes AS LONG

  exprRes = parseExpression(passStartIdx, passEndIdx, allowImplicit)
  IF exprRes = 0 THEN
    genForceNumericIntEx = 0
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError passErrMsg$, ASIS, 0
    genForceNumericIntEx = 0
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
    opMode = MODE_SSE_DOUBLE
    IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
    ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
  END IF

  exprIs.DataType = TYPE_LONG
  genForceNumericIntEx = 1

END FUNCTION ' genForceNumericIntEx

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

  DIM targetVIdx AS LONG
  DIM iSub AS LONG
  DIM subIdx AS LONG
  DIM rbpOffset AS LONG

  targetVIdx = vIdx
  IF targetVIdx = TEMP_HEAP_VAR_IDX THEN targetVIdx = internalTempHeapSymbolIdx
  IF targetVIdx = PROCESS_HEAP_VAR_IDX THEN targetVIdx = internalProcessHeapSymbolIdx

  IF symbols(targetVIdx).DataType = TYPE_UNDEFINED THEN
    ESCAPETEXT2 "GSRL FATAL IN genSymbolRouteLea", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(targetVIdx).RecordName)
  END IF

  IF symbols(targetVIdx).IsLocal = 1 AND symbols(targetVIdx).IsShared = 0 THEN
    subIdx = -1
    FOR iSub = 0 TO subCount - 1
      IF subs(iSub).ScopeID = symbols(targetVIdx).ScopeID THEN
        subIdx = iSub
        EXIT FOR
      END IF
    NEXT

    IF subIdx <> -1 THEN
      rbpOffset = symbols(targetVIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56

      ff = opLea(OP_TYPE_REG, destReg, OP_TYPE_MEM_RBP, rbpOffset, 64)
      genSymbolRouteLea = 1
      EXIT FUNCTION
    END IF
  END IF

  ' Global fallback
  ff = opLea(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64)
  addPatch PATCH_VAR, ff, targetVIdx, 0

  genSymbolRouteLea = 1

END FUNCTION ' genSymbolRouteLea

''''''''''''''''''''''''
FUNCTION genSymbolRouteMov (destType AS LONG, destInfo AS LONG, srcType AS LONG, srcInfo AS _INTEGER64, opSize AS LONG, vIdx AS LONG)

  DIM targetVIdx AS LONG
  DIM iSub AS LONG
  DIM subIdx AS LONG
  DIM rbpOffset AS LONG
  DIM fDestType AS LONG
  DIM fDestInfo AS LONG
  DIM fSrcType AS LONG
  DIM fSrcInfo AS _INTEGER64

  targetVIdx = vIdx
  IF targetVIdx = TEMP_HEAP_VAR_IDX THEN targetVIdx = internalTempHeapSymbolIdx
  IF targetVIdx = PROCESS_HEAP_VAR_IDX THEN targetVIdx = internalProcessHeapSymbolIdx

  IF symbols(targetVIdx).DataType = TYPE_UNDEFINED THEN
    ESCAPETEXT2 "GSRM FATAL IN genSymbolRouteMov", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(targetVIdx).RecordName)
  END IF

  fDestType = destType
  fDestInfo = destInfo
  fSrcType = srcType
  fSrcInfo = srcInfo

  IF symbols(targetVIdx).IsLocal = 1 AND symbols(targetVIdx).IsShared = 0 THEN
    subIdx = -1
    FOR iSub = 0 TO subCount - 1
      IF subs(iSub).ScopeID = symbols(targetVIdx).ScopeID THEN
        subIdx = iSub
        EXIT FOR
      END IF
    NEXT

    IF subIdx <> -1 THEN
      rbpOffset = symbols(targetVIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56

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
      IF (symbols(targetVIdx).DataType = TYPE_STRING OR symbols(targetVIdx).DataType = TYPE_UDT) AND symbols(targetVIdx).IsArray = 0 THEN
        IF srcType = OP_TYPE_MEM_RIP AND destType = OP_TYPE_REG THEN
          ff = opLea(OP_TYPE_REG, destInfo, OP_TYPE_MEM_RBP, rbpOffset, 64)
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
  addPatch PATCH_VAR, ff, targetVIdx, 0

  genSymbolRouteMov = 1

END FUNCTION ' genSymbolRouteMov

''''''''''''''''''''''''
FUNCTION genSymbolRouteSSE (sseOpCode AS LONG, destType AS LONG, destInfo AS LONG, srcType AS LONG, srcInfo AS LONG, opMode AS LONG, vIdx AS LONG)

  ' Automatically routes variable access to either global memory (RIP-relative) or local SUB/FUNCTION stack frames (RBP-relative)
  ' This prevents the frontend from needing massive boilerplate blocks to determine variable scope on every memory read/write

  DIM targetVIdx AS LONG
  DIM iSub AS LONG
  DIM subIdx AS LONG
  DIM rbpOffset AS LONG
  DIM fDestType AS LONG
  DIM fDestInfo AS LONG
  DIM fSrcType AS LONG
  DIM fSrcInfo AS LONG

  targetVIdx = vIdx
  IF targetVIdx = TEMP_HEAP_VAR_IDX THEN targetVIdx = internalTempHeapSymbolIdx
  IF targetVIdx = PROCESS_HEAP_VAR_IDX THEN targetVIdx = internalProcessHeapSymbolIdx

  IF symbols(targetVIdx).DataType = TYPE_UNDEFINED THEN
    ESCAPETEXT2 "GSRS FATAL IN genSymbolRouteSSE", "TYPE_UNDEFINED on symbol: " + RTRIM$(symbols(targetVIdx).RecordName)
  END IF

  fDestType = destType
  fDestInfo = destInfo
  fSrcType = srcType
  fSrcInfo = srcInfo

  IF symbols(targetVIdx).IsLocal = 1 AND symbols(targetVIdx).IsShared = 0 THEN
    subIdx = -1
    FOR iSub = 0 TO subCount - 1
      IF subs(iSub).ScopeID = symbols(targetVIdx).ScopeID THEN
        subIdx = iSub
        EXIT FOR
      END IF
    NEXT

    IF subIdx <> -1 THEN
      rbpOffset = symbols(targetVIdx).LocalOffset - subs(subIdx).LocalFrameSize - 56

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
  addPatch PATCH_VAR, ff, targetVIdx, 0

  genSymbolRouteSSE = 1

END FUNCTION ' genSymbolRouteSSE

''''''''''''''''''''''''
SUB genTempHeapReset

  ' Load !TEMP_HEAP_START into rax
  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, internalTempHeapStartSymbolIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  ' mov [rip + TEMP_HEAP_VAR_IDX], rax
  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, TEMP_HEAP_VAR_IDX)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

END SUB ' genTempHeapReset

''''''''''''''''''''''''
FUNCTION genUpdateStringDescriptor (descVarIdx, dataReg, lenReg)

  ' Load descriptor pointer
  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, descVarIdx)
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
    genUpdateStringDescriptor = 0
    EXIT FUNCTION
  END IF

  ' mov [descReg], dataReg
  ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_REG, dataReg, 64)

  ' mov [descReg + 8], lenReg
  ff = opMov(OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), OP_TYPE_REG, lenReg, 64)

  genUpdateStringDescriptor = 1

END FUNCTION ' genUpdateStringDescriptor

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
SUB initColors

  sysColor.flashTextClr = 14
  sysColor.gray = 8
  sysColor.focusBorder = 10

END SUB ' initColors

''''''''''''''''''''''''
SUB initFileNames

  fileNameBMP$ = "PALETTE.BMP"
  fileNameCode$ = "CODE.TXT"
  fileNameOut$ = "Output.exe"
  fileNameErr$ = "ErrorReport.txt"

END SUB ' initFileNames

''''''''''''''''''''''''
SUB initIntrinsics

  intrinsicCount = 0

  addIntrinsic "ASC", TYPE_LONG
  addIntrinsic "ATN", TYPE_DOUBLE
  addIntrinsic "CHR$", TYPE_STRING
  addIntrinsic "INT", TYPE_LONG
  addIntrinsic "LEFT$", TYPE_STRING
  addIntrinsic "LEN", TYPE_LONG
  addIntrinsic "LTRIM$", TYPE_STRING
  addIntrinsic "MID$", TYPE_STRING
  addIntrinsic "RIGHT$", TYPE_STRING
  addIntrinsic "RTRIM$", TYPE_STRING
  addIntrinsic "STR$", TYPE_STRING
  addIntrinsic "UCASE$", TYPE_STRING
  addIntrinsic "VAL", TYPE_LONG
  addIntrinsic "_KEYDOWN", TYPE_LONG

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
  addKeyword "_DISPLAY", TOK_DISPLAY, 0
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
  addKeyword "_LIMIT", TOK_LIMIT, 0
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

END SUB ' initPalettes

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
  ' used by emitPrintNumber, emitInput, and TIRA backend API calls.

  currentFrameSize = 32 ' Win64 shadow space

  stack.slotOverlapped = addStackSpace(8) ' MUST be at 32 for WriteFile/ReadFile 5th param!
  stack.slotHandleSave = addStackSpace(8)
  stack.slotBytesWritten = addStackSpace(8)
  stack.slotNumptrSpill = addStackSpace(8)
  stack.slotReadBuffer = addStackSpace(8)

  stack.scratchEndPtr = addStackSpace(8)
  stack.scratchStartPtr = addStackSpace(8)
  stack.scratchGfxSpill = addStackSpace(8)

  ' Provide exactly 32 bytes for the integer-to-ASCII conversion buffer
  stack.numItoaBuffer = addStackSpace(32)

  ' Allocate 24 bytes for temporary descriptor creation safely
  stack.TMP_DESC_PTR = addStackSpace(24)

  ' Align the frame and save to consoleFrameSize
  stack.consoleFrameSize = addStackSpace(-1)

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
  stack.GFX_SETUP_FRAME = addStackSpace(-1)

  '''' Graphics WndProc frame
  ' Must reserve 112 bytes for stack arguments (CreateFontA needs 14 args = 32 shadow + 80 stack)
  ' If we don't reserve this, GDI API calls will overwrite our local variables like PAINTSTRUCT!
  currentFrameSize = 112

  stack.WNDPROC_SLOT_TEXTLEN = addStackSpace(8)
  stack.WNDPROC_SLOT_PAINTSTRUCT = addStackSpace(72)

  ' Local variables for WndProc
  stack.WNDPROC_SLOT_FB_PTR = addStackSpace(8)
  stack.WNDPROC_SLOT_FB_Y = addStackSpace(8)
  stack.WNDPROC_SLOT_FB_X = addStackSpace(8)
  stack.WNDPROC_SLOT_HDC = addStackSpace(8)
  stack.WNDPROC_SLOT_COUNT = addStackSpace(8)
  stack.WNDPROC_SLOT_BASE = addStackSpace(8)
  stack.WNDPROC_SLOT_Y = addStackSpace(8)
  stack.WNDPROC_SLOT_HWND = addStackSpace(8)

  ' Memory DC handling slots
  stack.WNDPROC_SLOT_MEMDC = addStackSpace(8)
  stack.WNDPROC_SLOT_HBITMAP = addStackSpace(8)
  stack.WNDPROC_SLOT_OLD_HBITMAP = addStackSpace(8)
  stack.WNDPROC_SLOT_HFONT = addStackSpace(8)
  stack.WNDPROC_SLOT_OLD_HFONT = addStackSpace(8)

  ' Align the WndProc frame to 16 bytes, adding 8 for the return address alignment
  stack.GFX_WNDPROC_FRAME = addStackSpace(-1)

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

  emitByteCode &H48 ' REX.W
  emitByteCode &H81 ' ALU format 81
  emitByteCode &HC4 ' ModRM for ADD RSP
  emitBytes32 wVal

  stack.currentStackOffset = stack.currentStackOffset - wVal
  ff = updateStackAlignment

END SUB ' opAddRsp32

''''''''''''''''''''''''
FUNCTION opALU (aluOpCode, destType, destInfo, srcType, srcInfo, opSizeOrFlag)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG
  DIM useImm8 AS LONG

  DIM opBase03 AS LONG
  DIM opBase01 AS LONG
  DIM opBase81 AS LONG
  DIM opBase83 AS LONG

  tempRet = 0 ' Default return value, 0 means no patch position

  IF opSizeOrFlag = MODE_RIP THEN
    srcReg = srcInfo
    rex = &H48
    IF srcReg >= 8 THEN rex = rex OR &H04
    emitByteCode rex
    emitByteCode &H01 + (aluOpCode * 8)
    modRM = ((srcReg AND 7) * 8) + 5
    emitByteCode modRM
    tempRet = emitPos
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

  rex = 0

  ' X64 requirement: When accessing 8-bit registers 4-7 (SPL, BPL, SIL, DIL)
  ' an empty REX prefix must be present, otherwise it maps to AH, CH, DH, BH
  IF opSizeOrFlag = 8 THEN
    IF destType = OP_TYPE_REG THEN
      IF destInfo >= 4 AND destInfo <= 7 THEN rex = rex OR &H40
    END IF
    IF srcType = OP_TYPE_REG OR srcType = OP_TYPE_REG_ALT THEN
      IF srcInfo >= 4 AND srcInfo <= 7 THEN rex = rex OR &H40
    END IF
  END IF

  IF opSizeOrFlag = 16 THEN emitByteCode &H66

  SELECT CASE destType

    CASE OP_TYPE_ACC ' Explicit Accumulator-to-Immediate operations
      ' Requires srcType to be OP_TYPE_IMM
      IF opSizeOrFlag = 64 THEN rex = rex OR &H8
      IF rex > 0 THEN emitByteCode &H40 OR rex

      IF opSizeOrFlag = 8 THEN
        ' 8-bit accumulator (AL) uses base + &H04
        emitByteCode (aluOpCode * 8) + &H04
        emitByteCode (srcInfo AND 255)
      ELSE
        ' 16/32/64-bit accumulator (AX/EAX/RAX) uses base + &H05
        emitByteCode (aluOpCode * 8) + &H05

        IF opSizeOrFlag = 16 THEN
          emitByteCode (srcInfo AND 255)
          emitByteCode ((srcInfo \ 256) AND 255)
        ELSE
          ' 32-bit and 64-bit both take a 32-bit immediate here
          emitBytes32 srcInfo
        END IF
      END IF

    CASE OP_TYPE_REG
      destReg = destInfo

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Register
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF srcReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex

          emitByteCode opBase03 + (aluOpCode * 8)
          modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_REG_ALT
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          ' Because dest is now in the R/M field, it gets the REX.B bit
          IF destReg >= 8 THEN rex = rex OR &H1
          ' Because src is now in the Reg field, it gets the REX.R bit
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex

          emitByteCode opBase01 + (aluOpCode * 8)
          modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_IMM ' Immediate-to-Register
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex

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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase03 + (aluOpCode * 8)
          modRM = ((destReg AND 7) * 8) + 5
          emitByteCode modRM
          tempRet = emitPos
          emitBytes32 0

        CASE OP_TYPE_MEM_RSP ' Memory-to-Register (RSP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase03 + (aluOpCode * 8)
          IF srcInfo >= -128 AND srcInfo <= 127 THEN
            modRM = &H44 + ((destReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode srcInfo AND 255
          ELSE
            modRM = &H84 + ((destReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24
            emitBytes32 srcInfo
          END IF

        CASE OP_TYPE_MEM_RBP ' Memory-to-Register (RBP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase03 + (aluOpCode * 8)
          modRM = &H85 + ((destReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 srcInfo

        CASE OP_TYPE_MEM_REG ' Memory-to-Register (Register-Indirect, no displacement)
          baseReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase03 + (aluOpCode * 8)

          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
            END IF
          END IF

        CASE OP_TYPE_MEM_REG_DISP8 ' Memory-to-Register (Register-Indirect with 8-bit disp)
          baseReg = srcInfo AND 15
          disp8 = (srcInfo \ 256) AND 255
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase03 + (aluOpCode * 8)

          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RIP ' Register-to-Memory (RIP-relative)
      srcReg = srcInfo
      IF opSizeOrFlag = 64 THEN rex = rex OR &H8
      IF srcReg >= 8 THEN rex = rex OR &H4
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode opBase01 + (aluOpCode * 8)
      modRM = ((srcReg AND 7) * 8) + 5
      emitByteCode modRM
      tempRet = emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Memory (RSP-relative)
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase01 + (aluOpCode * 8)
          IF destInfo >= -128 AND destInfo <= 127 THEN
            modRM = &H44 + ((srcReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode destInfo AND 255
          ELSE
            modRM = &H84 + ((srcReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24
            emitBytes32 destInfo
          END IF

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RSP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF rex > 0 THEN emitByteCode &H40 OR rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN
            emitByteCode opBase83
          ELSE
            emitByteCode opBase81
          END IF

          IF destInfo >= -128 AND destInfo <= 127 THEN
            emitByteCode &H44 + (aluOpCode * 8)
            emitByteCode &H24
            emitByteCode destInfo AND 255
          ELSE
            emitByteCode &H84 + (aluOpCode * 8)
            emitByteCode &H24
            emitBytes32 destInfo
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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase01 + (aluOpCode * 8)
          modRM = &H85 + ((srcReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 destInfo

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RBP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF rex > 0 THEN emitByteCode &H40 OR rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN
            emitByteCode opBase83
          ELSE
            emitByteCode opBase81
          END IF

          emitByteCode &H85 + (aluOpCode * 8)
          emitBytes32 destInfo

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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase01 + (aluOpCode * 8)

          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
            END IF
          END IF

        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN
            emitByteCode opBase83
          ELSE
            emitByteCode opBase81
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + (aluOpCode * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + (aluOpCode * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + (aluOpCode * 8) + baseRegMod
              emitByteCode modRM
            END IF
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

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = destInfo AND 15
      disp8 = (destInfo \ 256) AND 255

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase01 + (aluOpCode * 8)

          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
          END IF

        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex

          useImm8 = 0
          IF opSizeOrFlag = MODE_IMM8 THEN
            useImm8 = 1
          ELSE
            IF srcInfo >= -128 AND srcInfo <= 127 THEN useImm8 = 1
          END IF
          IF opSizeOrFlag = 8 THEN useImm8 = 1

          IF useImm8 = 1 THEN
            emitByteCode opBase83
          ELSE
            emitByteCode opBase81
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + (aluOpCode * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + (aluOpCode * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
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

  END SELECT ' destType

  opALU = tempRet

END FUNCTION ' opALU

''''''''''''''''''''''''
FUNCTION opALU_SIB (aluOpCode, destIsMem AS LONG, valType AS LONG, valInfo AS _INTEGER64, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG, opSize AS LONG)

  DIM rex AS _UNSIGNED _BYTE
  DIM modBits AS LONG
  DIM scaleBits AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM sibByte AS _UNSIGNED _BYTE
  DIM tempRet AS LONG
  DIM regField AS LONG
  DIM useImm8 AS LONG

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

  DIM tempRet AS LONG

  tempRet = 0

  STACKSAFETYCHECK = 1

  IF STACKSAFETYCHECK = 1 THEN
    IF (stack.currentStackOffset AND 15) <> 0 THEN
      err1$ = "FATAL: Unaligned call offset:" + LTRIM$(STR$(stack.currentStackOffset)) + " bytes"
      IF currentLineNumber > 0 AND currentLineNumber <= EDITOR_LINE_MAX THEN
        err1$ = err1$ + " Line: " + LTRIM$(STR$(currentLineNumber))
      END IF
      IF currentSubName$ <> "" THEN
        err1$ = err1$ + " in SUB: " + currentSubName$
      END IF

      err2$ = ""
      IF currentLineNumber > 0 AND currentLineNumber <= EDITOR_LINE_MAX THEN
        IF compileText$(currentLineNumber) <> "" THEN
          err2$ = "[" + LTRIM$(RTRIM$(compileText$(currentLineNumber))) + "]"
        END IF
      END IF
      err2$ = err2$ + " (wInfo: " + LTRIM$(STR$(wInfo)) + ", wMode: " + LTRIM$(STR$(wMode)) + ")"

      ESCAPETEXT2 err1$, err2$
    END IF
  END IF


  IF wMode = CALLMODE_IAT THEN
    emitByteCode &HFF
    emitByteCode &H15

    addPatch PATCH_IAT, emitPos, wInfo, 0
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
      opCall = 0
      EXIT FUNCTION
    END IF

    tempRet = emitPos
    emitBytes32 0
  ELSE
    IF wMode = CALLMODE_REL32 THEN
      emitByteCode &HE8
      tempRet = emitPos
      emitBytes32 0
    END IF
  END IF

  opCall = tempRet

END FUNCTION ' opCall

''''''''''''''''''''''''
SUB opDecReg (wReg, opSize)

  ' Only supports registers, unlike the opUnary version, but generates less boilerplate

  DIM rex AS _UNSIGNED _BYTE

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
FUNCTION opImul (destReg AS LONG, srcType AS LONG, srcInfo AS _INTEGER64, immVal AS _INTEGER64, opMode AS LONG)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG
  DIM useImm8 AS LONG
  DIM is64Bit AS LONG
  DIM isImmMode AS LONG

  tempRet = 0
  rex = 0
  is64Bit = 0
  isImmMode = 0

  IF opMode = MODE_IMUL64_REG OR opMode = MODE_IMUL64_IMM OR opMode = MODE_IMUL64_IMM32 THEN is64Bit = 1
  IF opMode = MODE_IMUL32_IMM OR opMode = MODE_IMUL64_IMM OR opMode = MODE_IMUL32_IMM32 OR opMode = MODE_IMUL64_IMM32 THEN isImmMode = 1

  IF is64Bit = 1 THEN rex = rex OR &H08
  IF destReg >= 8 THEN rex = rex OR &H04

  SELECT CASE srcType

    CASE OP_TYPE_REG
      srcReg = srcInfo
      IF srcReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex

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
      IF rex > 0 THEN emitByteCode &H40 OR rex

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
      tempRet = emitPos
      emitBytes32 0

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_RSP
      IF rex > 0 THEN emitByteCode &H40 OR rex

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
        modRM = &H44 + ((destReg AND 7) * 8)
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode srcInfo AND 255
      ELSE
        modRM = &H84 + ((destReg AND 7) * 8)
        emitByteCode modRM
        emitByteCode &H24
        emitBytes32 srcInfo
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
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex

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

      baseRegMod = baseReg AND 7
      IF baseRegMod = 5 THEN
        modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode 0
      ELSE
        IF baseRegMod = 4 THEN
          modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
        ELSE
          modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
        END IF
      END IF

      IF isImmMode = 1 THEN
        IF useImm8 = 1 THEN
          emitByteCode (immVal AND 255)
        ELSE
          emitBytes32 immVal
        END IF
      END IF

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = srcInfo AND 15
      disp8 = (srcInfo \ 256) AND 255
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex

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

      baseRegMod = baseReg AND 7
      IF baseRegMod = 4 THEN
        modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode disp8
      ELSE
        modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode disp8
      END IF

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

  ' Only supports registers, unlike the opUnary version, but generates less boilerplate

  DIM rex AS _UNSIGNED _BYTE

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

  DIM tempRet AS LONG

  tempRet = 0

  IF wJumpType = JCC_TYPE_SHORT THEN
    IF condCode = JCC_JMP THEN
      emitByteCode &HEB
    ELSE
      emitByteCode &H70 + condCode
    END IF

    IF wMode = JCC_MODE_FORWARD THEN
      tempRet = emitPos
      emitByteCode 0
    ELSE
      emitByteCode (wTarget - (emitPos + 1)) AND 255
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
      tempRet = emitPos
      emitBytes32 0
    ELSE
      emitBytes32 wTarget - (emitPos + 4)
    END IF
  END IF


  opJcc = tempRet

END FUNCTION ' opJcc

''''''''''''''''''''''''
FUNCTION opLea (destType, destInfo AS LONG, srcType, srcInfo AS _INTEGER64, opSizeOrFlag)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG

  tempRet = 0 ' Default return value
  rex = 0

  IF destType <> OP_TYPE_REG THEN
    opLea = tempRet
    EXIT FUNCTION
  END IF

  destReg = destInfo

  IF opSizeOrFlag = 64 THEN rex = rex OR &H8
  IF destReg >= 8 THEN rex = rex OR &H4

  SELECT CASE srcType

    CASE OP_TYPE_MEM_RIP
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8D
      modRM = ((destReg AND 7) * 8) + 5
      emitByteCode modRM
      tempRet = emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8D
      IF srcInfo >= -128 AND srcInfo <= 127 THEN
        modRM = &H44 + ((destReg AND 7) * 8)
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode srcInfo AND 255
      ELSE
        modRM = &H84 + ((destReg AND 7) * 8)
        emitByteCode modRM
        emitByteCode &H24
        emitBytes32 srcInfo
      END IF

    CASE OP_TYPE_MEM_RBP
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8D
      modRM = &H85 + ((destReg AND 7) * 8)
      emitByteCode modRM
      emitBytes32 srcInfo

    CASE OP_TYPE_MEM_REG
      baseReg = srcInfo AND 15
      IF baseReg >= 8 THEN rex = rex OR &H1
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8D

      baseRegMod = baseReg AND 7
      IF baseRegMod = 5 THEN
        modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode 0
      ELSE
        IF baseRegMod = 4 THEN
          modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
        ELSE
          modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
        END IF
      END IF

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = srcInfo AND 15
      disp8 = (srcInfo \ 256) AND 255
      IF baseReg >= 8 THEN rex = rex OR &H1
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8D

      baseRegMod = baseReg AND 7
      IF baseRegMod = 4 THEN
        modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode disp8
      ELSE
        modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode disp8
      END IF

  END SELECT ' srcType

  opLea = tempRet

END FUNCTION ' opLea

''''''''''''''''''''''''
FUNCTION opLea_SIB (destReg AS LONG, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG, opSize AS LONG)

  DIM rex AS _UNSIGNED _BYTE
  DIM modBits AS LONG
  DIM scaleBits AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM sibByte AS _UNSIGNED _BYTE
  DIM tempRet AS LONG

  tempRet = 0
  rex = 0

  IF opSize = 64 THEN rex = rex OR &H08
  IF destReg >= 8 THEN rex = rex OR &H04
  IF indexReg >= 8 THEN rex = rex OR &H02
  IF baseReg >= 8 THEN rex = rex OR &H01

  IF rex > 0 THEN emitByteCode &H40 OR rex

  emitByteCode &H8D

  IF dispVal = 0 AND (baseReg AND 7) <> 5 THEN
    modBits = 0
  ELSE
    IF dispVal >= -128 AND dispVal <= 127 THEN
      modBits = 1
    ELSE
      modBits = 2
    END IF
  END IF

  modRM = (modBits * 64) + ((destReg AND 7) * 8) + 4
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

  opLea_SIB = tempRet

END FUNCTION ' opLea_SIB


''''''''''''''''''''''''
FUNCTION opLeaRegMemRIP (wReg)

  emitByteCode &H48
  emitByteCode &H8D
  modRM = (wReg * 8) + 5
  emitByteCode modRM
  retPos = emitPos
  emitBytes32 0

  opLeaRegMemRIP = retPos

END FUNCTION ' opLeaRegMemRIP

''''''''''''''''''''''''
SUB opLeaRspDisp32 (wReg, wDisp)

  ' Using opLea instead of this function will output 5 bytes instead of 8 bytes since opLea compresses offsets under 128

  emitByteCode &H48
  emitByteCode &H8D
  modRM = 128 + (wReg * 8) + 4
  emitByteCode modRM
  emitByteCode &H24
  emitBytes32 wDisp

END SUB ' opLeaRspDisp32

''''''''''''''''''''''''
FUNCTION opMov (destType, destInfo AS LONG, srcType, srcInfo AS _INTEGER64, opSizeOrFlag)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM uVal64 AS _UNSIGNED _INTEGER64
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM is8bitSource AS LONG
  DIM is0FPrefix AS LONG
  DIM opCodeByte AS _UNSIGNED _BYTE

  opMov = 0 ' Default return value, 0 means no patch position

  SELECT CASE opSizeOrFlag

    CASE MODE_MOVZX32_8, MODE_MOVZX32_16, MODE_MOVZX64_8, MODE_MOVZX64_16, MODE_MOVSX32_8, MODE_MOVSX32_16, MODE_MOVSX64_8, MODE_MOVSX64_16, MODE_MOVSXD
      ' Handles movzx, movsx, movsxd
      IF destType <> OP_TYPE_REG THEN
        opMov = 0
        EXIT FUNCTION
      END IF

      destReg = destInfo
      rex = 0
      is8bitSource = 0
      is0FPrefix = 1

      IF opSizeOrFlag = MODE_MOVZX64_8 OR opSizeOrFlag = MODE_MOVZX64_16 OR opSizeOrFlag = MODE_MOVSX64_8 OR opSizeOrFlag = MODE_MOVSX64_16 OR opSizeOrFlag = MODE_MOVSXD THEN
        rex = rex OR &H8 ' REX.W for 64-bit destination
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

      IF destReg >= 8 THEN rex = rex OR &H4 ' REX.R for destination

      SELECT CASE srcType

        CASE OP_TYPE_REG ' MOVZX/MOVSX r_dest, r_src
          srcReg = srcInfo
          IF srcReg >= 8 THEN rex = rex OR &H1 ' REX.B for source
          IF is8bitSource = 1 THEN
            IF srcReg >= 4 AND srcReg <= 7 THEN rex = rex OR &H40 ' REX prefix for SPL, BPL, SIL, DIL
          END IF

          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_MEM_RIP ' MOVZX/MOVSX r_dest, [rip+disp32]
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          modRM = ((destReg AND 7) * 8) + 5
          emitByteCode modRM
          opMov = emitPos
          emitBytes32 0

        CASE OP_TYPE_MEM_RSP ' MOVZX/MOVSX r_dest, [rsp+disp]
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          IF srcInfo >= -128 AND srcInfo <= 127 THEN ' disp8
            modRM = &H44 + ((destReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24 ' SIB
            emitByteCode srcInfo AND 255
          ELSE ' disp32
            modRM = &H84 + ((destReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24 ' SIB
            emitBytes32 srcInfo
          END IF

        CASE OP_TYPE_MEM_RBP ' MOVZX/MOVSX r_dest, [rbp+disp32]
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          modRM = &H85 + ((destReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 srcInfo

        CASE OP_TYPE_MEM_REG ' MOVZX/MOVSX r_dest, [base_reg]
          baseReg = srcInfo AND 15
          IF baseReg >= 8 THEN rex = rex OR &H1 ' REX.B for base
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
            END IF
          END IF

        CASE OP_TYPE_MEM_REG_DISP8 ' MOVZX/MOVSX r_dest, [base_reg+disp8]
          baseReg = srcInfo AND 15
          disp8 = (srcInfo \ 256) AND 255
          IF baseReg >= 8 THEN rex = rex OR &H1 ' REX.B for base
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF is0FPrefix = 1 THEN emitByteCode &H0F
          emitByteCode opCodeByte
          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
          END IF

      END SELECT ' srcType

      EXIT FUNCTION ' Extension logic is complete, exit

  END SELECT ' opSizeOrFlag

  IF opSizeOrFlag = MODE_IMM64 THEN
    destReg = destInfo
    rex = &H48
    IF destReg >= 8 THEN rex = rex OR &H01
    emitByteCode rex
    emitByteCode &HB8 + (destReg AND 7)

    uVal64 = srcInfo
    FOR ii = 1 TO 8
      emitByteCode (uVal64 AND 255)
      uVal64 = uVal64 \ 256
    NEXT
    EXIT FUNCTION
  END IF

  IF opSizeOrFlag = MODE_RIP THEN
    srcReg = srcInfo
    rex = &H48
    IF srcReg >= 8 THEN rex = rex OR &H04
    emitByteCode rex
    emitByteCode &H89
    modRM = ((srcReg AND 7) * 8) + 5
    emitByteCode modRM
    opMov = emitPos
    emitBytes32 0
    EXIT FUNCTION
  END IF

  rex = 0

  SELECT CASE destType

    CASE OP_TYPE_REG
      destReg = destInfo

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Register
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H1
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex

          IF opSizeOrFlag = 8 THEN
            emitByteCode &H88
          ELSE
            emitByteCode &H89
          END IF
          modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_REG_ALT
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          ' Because dest is now in the Reg field, it gets the REX.R bit
          IF destReg >= 8 THEN rex = rex OR &H4
          ' Because src is now in the R/M field, it gets the REX.B bit
          IF srcReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex

          IF opSizeOrFlag = 8 THEN
            emitByteCode &H8A
          ELSE
            emitByteCode &H8B
          END IF
          modRM = &HC0 + ((destReg AND 7) * 8) + (srcReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_IMM ' Immediate-to-Register
          IF opSizeOrFlag = 8 THEN
            IF destReg >= 8 THEN rex = rex OR &H1 ' REX.B
            IF rex > 0 THEN emitByteCode &H40 OR rex
            emitByteCode &HB0 + (destReg AND 7)
            emitByteCode (srcInfo AND 255)
          ELSE
            IF opSizeOrFlag = 64 THEN
              uVal64 = srcInfo
              ' Check if immediate fits in 32-bit signed value for smaller encoding
              IF srcInfo >= -2147483648 AND srcInfo <= 2147483647 THEN
                rex = rex OR &H8 ' REX.W
                IF destReg >= 8 THEN rex = rex OR &H1 ' REX.B
                IF rex > 0 THEN emitByteCode &H40 OR rex
                emitByteCode &HC7
                modRM = &HC0 + (destReg AND 7)
                emitByteCode modRM
                emitBytes32 srcInfo
              ELSE
                rex = rex OR &H8 ' REX.W
                IF destReg >= 8 THEN rex = rex OR &H1 ' REX.B
                IF rex > 0 THEN emitByteCode &H40 OR rex
                emitByteCode &HB8 + (destReg AND 7)
                FOR ii = 1 TO 8
                  emitByteCode (uVal64 AND 255)
                  uVal64 = uVal64 \ 256
                NEXT
              END IF
            ELSE ' opSizeOrFlag = 32 or 16
              IF destReg >= 8 THEN rex = rex OR &H1 ' REX.B
              IF opSizeOrFlag = 16 THEN emitByteCode &H66
              IF rex > 0 THEN emitByteCode &H40 OR rex
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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4 ' destReg is in 'reg' field
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H8A
          ELSE
            emitByteCode &H8B
          END IF
          modRM = ((destReg AND 7) * 8) + 5
          emitByteCode modRM
          opMov = emitPos
          emitBytes32 0

        CASE OP_TYPE_MEM_RSP ' Memory-to-Register (RSP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H8A
          ELSE
            emitByteCode &H8B
          END IF
          IF srcInfo >= -128 AND srcInfo <= 127 THEN ' disp8
            modRM = &H44 + ((destReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24 ' SIB
            emitByteCode srcInfo AND 255
          ELSE ' disp32
            modRM = &H84 + ((destReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24 ' SIB
            emitBytes32 srcInfo
          END IF

        CASE OP_TYPE_MEM_RBP ' Memory-to-Register (RBP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H8A
          ELSE
            emitByteCode &H8B
          END IF
          modRM = &H85 + ((destReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 srcInfo

        CASE OP_TYPE_MEM_REG ' Memory-to-Register (Register-Indirect, no displacement)
          baseReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H8A
          ELSE
            emitByteCode &H8B
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
            END IF
          END IF

        CASE OP_TYPE_MEM_REG_DISP8 ' Memory-to-Register (Register-Indirect with 8-bit disp)
          baseReg = srcInfo AND 15
          disp8 = (srcInfo \ 256) AND 255
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H8A
          ELSE
            emitByteCode &H8B
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
          END IF

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RIP ' Register-to-Memory (RIP-relative)
      srcReg = srcInfo
      IF opSizeOrFlag = 64 THEN rex = rex OR &H8
      IF srcReg >= 8 THEN rex = rex OR &H4
      IF opSizeOrFlag = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode &H40 OR rex
      IF opSizeOrFlag = 8 THEN
        emitByteCode &H88
      ELSE
        emitByteCode &H89
      END IF
      modRM = ((srcReg AND 7) * 8) + 5
      emitByteCode modRM
      opMov = emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Memory (RSP-relative)
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H88
          ELSE
            emitByteCode &H89
          END IF
          IF destInfo >= -128 AND destInfo <= 127 THEN ' disp8
            modRM = &H44 + ((srcReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24 ' SIB
            emitByteCode destInfo AND 255
          ELSE ' disp32
            modRM = &H84 + ((srcReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24 ' SIB
            emitBytes32 destInfo
          END IF

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RSP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &HC6
          ELSE
            emitByteCode &HC7
          END IF
          IF destInfo >= -128 AND destInfo <= 127 THEN ' disp8
            emitByteCode &H44 ' ModR/M for [RSP+disp8], reg=0
            emitByteCode &H24 ' SIB
            emitByteCode destInfo AND 255
          ELSE ' disp32
            emitByteCode &H84 ' ModR/M for [RSP+disp32], reg=0
            emitByteCode &H24 ' SIB
            emitBytes32 destInfo
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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H88
          ELSE
            emitByteCode &H89
          END IF
          modRM = &H85 + ((srcReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 destInfo

        CASE OP_TYPE_IMM ' Immediate-to-Memory (RBP-relative)
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &HC6
          ELSE
            emitByteCode &HC7
          END IF
          emitByteCode &H85 ' ModR/M for [RBP+disp32], reg=0
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

    CASE OP_TYPE_MEM_REG
      baseReg = destInfo AND 15

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H88
          ELSE
            emitByteCode &H89
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
            END IF
          END IF

        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &HC6
          ELSE
            emitByteCode &HC7
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + baseRegMod
              emitByteCode modRM
            END IF
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

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = destInfo AND 15
      disp8 = (destInfo \ 256) AND 255

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &H88
          ELSE
            emitByteCode &H89
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
          END IF

        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF opSizeOrFlag = 16 THEN emitByteCode &H66
          IF rex > 0 THEN emitByteCode &H40 OR rex
          IF opSizeOrFlag = 8 THEN
            emitByteCode &HC6
          ELSE
            emitByteCode &HC7
          END IF

          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + baseRegMod ' reg is 0
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
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

  END SELECT ' destType

END FUNCTION ' opMov

''''''''''''''''''''''''
FUNCTION opMov_SIB (destIsMem AS LONG, valType AS LONG, valInfo AS _INTEGER64, baseReg AS LONG, indexReg AS LONG, scaleVal AS LONG, dispVal AS LONG, opSize AS LONG)

  DIM rex AS _UNSIGNED _BYTE
  DIM modBits AS LONG
  DIM scaleBits AS LONG
  DIM modRM AS _UNSIGNED _BYTE
  DIM sibByte AS _UNSIGNED _BYTE
  DIM tempRet AS LONG
  DIM regField AS LONG

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
FUNCTION opPop (passOpType, passOpInfo AS _INTEGER64, opSize)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG

  tempRet = 0
  rex = 0

  IF opSize = 16 THEN
    ESCAPETEXT "ERROR: 16-bit POP attempted, which breaks x64 stack alignment"
  END IF

  SELECT CASE passOpType

    CASE OP_TYPE_REG
      baseReg = passOpInfo
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H58 + (baseReg AND 7)

    CASE OP_TYPE_MEM_RIP
      emitByteCode &H8F
      modRM = 5 ' (0 * 8) + 5
      emitByteCode modRM
      tempRet = emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      emitByteCode &H8F
      IF passOpInfo >= -128 AND passOpInfo <= 127 THEN
        modRM = &H44 ' (0 * 8) + R/M=4, mod=1
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode passOpInfo AND 255
      ELSE
        modRM = &H84 ' (0 * 8) + R/M=4, mod=2
        emitByteCode modRM
        emitByteCode &H24
        emitBytes32 passOpInfo
      END IF

    CASE OP_TYPE_MEM_RBP
      emitByteCode &H8F
      ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
      modRM = &H85 ' (0 * 8) + R/M=5, mod=2
      emitByteCode modRM
      emitBytes32 passOpInfo

    CASE OP_TYPE_MEM_REG
      baseReg = passOpInfo AND 15
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8F

      baseRegMod = baseReg AND 7
      IF baseRegMod = 5 THEN
        modRM = &H40 + baseRegMod
        emitByteCode modRM
        emitByteCode 0
      ELSE
        IF baseRegMod = 4 THEN
          modRM = &H00 + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
        ELSE
          modRM = &H00 + baseRegMod
          emitByteCode modRM
        END IF
      END IF

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = passOpInfo AND 15
      disp8 = (passOpInfo \ 256) AND 255
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H8F

      baseRegMod = baseReg AND 7
      IF baseRegMod = 4 THEN
        modRM = &H40 + baseRegMod
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode disp8
      ELSE
        modRM = &H40 + baseRegMod
        emitByteCode modRM
        emitByteCode disp8
      END IF

  END SELECT ' passOpType

  stack.currentStackOffset = stack.currentStackOffset - 8
  ff = updateStackAlignment

  opPop = tempRet

END FUNCTION ' opPop

''''''''''''''''''''''''
SUB opPopReg (wReg)

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
FUNCTION opPush (passOpType, passOpInfo AS _INTEGER64, opSize)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG

  tempRet = 0
  rex = 0

  IF opSize = 16 THEN
    ESCAPETEXT "ERROR: 16-bit PUSH attempted, which breaks x64 stack alignment"
  END IF

  SELECT CASE passOpType

    CASE OP_TYPE_REG
      baseReg = passOpInfo
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &H50 + (baseReg AND 7)

    CASE OP_TYPE_IMM
      IF passOpInfo >= -128 AND passOpInfo <= 127 THEN
        emitByteCode &H6A
        emitByteCode passOpInfo AND 255
      ELSE
        emitByteCode &H68
        emitBytes32 passOpInfo
      END IF

    CASE OP_TYPE_MEM_RIP
      emitByteCode &HFF
      modRM = (6 * 8) + 5
      emitByteCode modRM
      tempRet = emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      emitByteCode &HFF
      IF passOpInfo >= -128 AND passOpInfo <= 127 THEN
        modRM = &H44 + (6 * 8)
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode passOpInfo AND 255
      ELSE
        modRM = &H84 + (6 * 8)
        emitByteCode modRM
        emitByteCode &H24
        emitBytes32 passOpInfo
      END IF

    CASE OP_TYPE_MEM_RBP
      emitByteCode &HFF
      ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
      modRM = &H85 + (6 * 8)
      emitByteCode modRM
      emitBytes32 passOpInfo

    CASE OP_TYPE_MEM_REG
      baseReg = passOpInfo AND 15
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &HFF

      baseRegMod = baseReg AND 7
      IF baseRegMod = 5 THEN
        modRM = &H40 + (6 * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode 0
      ELSE
        IF baseRegMod = 4 THEN
          modRM = &H00 + (6 * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
        ELSE
          modRM = &H00 + (6 * 8) + baseRegMod
          emitByteCode modRM
        END IF
      END IF

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = passOpInfo AND 15
      disp8 = (passOpInfo \ 256) AND 255
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF rex > 0 THEN emitByteCode &H40 OR rex
      emitByteCode &HFF

      baseRegMod = baseReg AND 7
      IF baseRegMod = 4 THEN
        modRM = &H40 + (6 * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode &H24
        emitByteCode disp8
      ELSE
        modRM = &H40 + (6 * 8) + baseRegMod
        emitByteCode modRM
        emitByteCode disp8
      END IF

  END SELECT ' passOpType

  stack.currentStackOffset = stack.currentStackOffset + 8
  ff = updateStackAlignment

  opPush = tempRet

END FUNCTION ' opPush

''''''''''''''''''''''''
SUB opPushReg (wReg)

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

  emitByteCode &HC3

END SUB ' opRet

''''''''''''''''''''''''
FUNCTION opSetcc (passCondCode, passDestReg)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM tempRet AS LONG

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

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE

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

  DIM tempRet AS LONG
  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM prefix AS LONG
  DIM opByte AS LONG
  DIM isReverse AS LONG
  DIM primaryReg AS LONG
  DIM rmReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG

  tempRet = 0
  rex = 0
  prefix = 0
  opByte = 0
  isReverse = 0

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
      rex = rex OR &H08
      opByte = &H2A

    CASE SSE_CVTTSD2SI
      rex = rex OR &H08
      opByte = &H2C
      isReverse = 0

    CASE SSE_CVTSD2SI
      rex = rex OR &H08
      opByte = &H2D
      isReverse = 0

    CASE SSE_CVTSS2SD, SSE_CVTSD2SS
      opByte = &H5A

    CASE SSE_MOVQ_XMM_REG
      prefix = &H66
      rex = rex OR &H08
      opByte = &H6E
      isReverse = 0

    CASE SSE_MOVQ_REG_XMM
      prefix = &H66
      rex = rex OR &H08
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
    IF destType = OP_TYPE_REG AND destInfo >= 8 THEN rex = rex OR &H01
    IF srcType = OP_TYPE_REG AND srcInfo >= 8 THEN rex = rex OR &H04
  ELSE
    IF destType = OP_TYPE_REG AND destInfo >= 8 THEN rex = rex OR &H04
    IF srcType = OP_TYPE_REG AND srcInfo >= 8 THEN rex = rex OR &H01
  END IF

  IF prefix <> 0 THEN emitByteCode prefix
  IF rex > 0 THEN emitByteCode &H40 OR rex
  emitByteCode &H0F
  emitByteCode opByte

  IF isReverse = 1 THEN
    primaryReg = srcInfo
    rmReg = destInfo

    SELECT CASE destType

      CASE OP_TYPE_REG
        modRM = &HC0 + ((primaryReg AND 7) * 8) + (rmReg AND 7)
        emitByteCode modRM

      CASE OP_TYPE_MEM_RIP
        modRM = ((primaryReg AND 7) * 8) + 5
        emitByteCode modRM
        tempRet = emitPos
        emitBytes32 0

      CASE OP_TYPE_MEM_RSP
        IF rmReg >= -128 AND rmReg <= 127 THEN
          modRM = &H44 + ((primaryReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode rmReg AND 255
        ELSE
          modRM = &H84 + ((primaryReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitBytes32 rmReg
        END IF

      CASE OP_TYPE_MEM_RBP
        modRM = &H85 + ((primaryReg AND 7) * 8)
        emitByteCode modRM
        emitBytes32 rmReg

      CASE OP_TYPE_MEM_REG
        baseReg = rmReg AND 15
        baseRegMod = baseReg AND 7
        IF baseRegMod = 5 THEN
          modRM = &H40 + ((primaryReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode 0
        ELSE
          IF baseRegMod = 4 THEN
            modRM = &H00 + ((primaryReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
          ELSE
            modRM = &H00 + ((primaryReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
          END IF
        END IF

      CASE OP_TYPE_MEM_REG_DISP8
        baseReg = rmReg AND 15
        disp8 = (rmReg \ 256) AND 255
        baseRegMod = baseReg AND 7
        IF baseRegMod = 4 THEN
          modRM = &H40 + ((primaryReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode disp8
        ELSE
          modRM = &H40 + ((primaryReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode disp8
        END IF

    END SELECT ' destType
  ELSE
    primaryReg = destInfo
    rmReg = srcInfo

    SELECT CASE srcType

      CASE OP_TYPE_REG
        modRM = &HC0 + ((primaryReg AND 7) * 8) + (rmReg AND 7)
        emitByteCode modRM

      CASE OP_TYPE_MEM_RIP
        modRM = ((primaryReg AND 7) * 8) + 5
        emitByteCode modRM
        tempRet = emitPos
        emitBytes32 0

      CASE OP_TYPE_MEM_RSP
        IF rmReg >= -128 AND rmReg <= 127 THEN
          modRM = &H44 + ((primaryReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode rmReg AND 255
        ELSE
          modRM = &H84 + ((primaryReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitBytes32 rmReg
        END IF

      CASE OP_TYPE_MEM_RBP
        modRM = &H85 + ((primaryReg AND 7) * 8)
        emitByteCode modRM
        emitBytes32 rmReg

      CASE OP_TYPE_MEM_REG
        baseReg = rmReg AND 15
        baseRegMod = baseReg AND 7
        IF baseRegMod = 5 THEN
          modRM = &H40 + ((primaryReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode 0
        ELSE
          IF baseRegMod = 4 THEN
            modRM = &H00 + ((primaryReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
          ELSE
            modRM = &H00 + ((primaryReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
          END IF
        END IF

      CASE OP_TYPE_MEM_REG_DISP8
        baseReg = rmReg AND 15
        disp8 = (rmReg \ 256) AND 255
        baseRegMod = baseReg AND 7
        IF baseRegMod = 4 THEN
          modRM = &H40 + ((primaryReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode disp8
        ELSE
          modRM = &H40 + ((primaryReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode disp8
        END IF

    END SELECT ' srcType

  END IF

  opSSE = tempRet

END FUNCTION ' opSSE

''''''''''''''''''''''''
SUB opString (wStrOp, wPrefix, wSize)

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

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG

  DIM opBase85 AS LONG
  DIM opBaseF7 AS LONG

  tempRet = 0

  opBase85 = &H85
  opBaseF7 = &HF7

  IF opSizeOrFlag = 8 THEN
    opBase85 = &H84
    opBaseF7 = &HF6
  END IF

  rex = 0

  IF opSizeOrFlag = 8 THEN
    IF destType = OP_TYPE_REG THEN
      IF destInfo >= 4 AND destInfo <= 7 THEN rex = rex OR &H40
    END IF
    IF srcType = OP_TYPE_REG THEN
      IF srcInfo >= 4 AND srcInfo <= 7 THEN rex = rex OR &H40
    END IF
  END IF

  IF opSizeOrFlag = 16 THEN emitByteCode &H66

  SELECT CASE destType

    CASE OP_TYPE_REG
      destReg = destInfo

      SELECT CASE srcType

        CASE OP_TYPE_REG ' Register-to-Register
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF destReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex

          emitByteCode opBase85
          modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
          emitByteCode modRM

        CASE OP_TYPE_IMM ' Immediate-to-Register
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex

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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF destReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase85
          ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
          modRM = &H85 + ((destReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 srcInfo

      END SELECT ' srcType

    CASE OP_TYPE_MEM_RIP ' Memory (RIP-relative)

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase85
          modRM = ((srcReg AND 7) * 8) + 5
          emitByteCode modRM
          tempRet = emitPos
          emitBytes32 0
        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBaseF7
          modRM = 5 ' reg field is 0
          emitByteCode modRM
          tempRet = emitPos
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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase85
          IF destInfo >= -128 AND destInfo <= 127 THEN
            modRM = &H44 + ((srcReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode destInfo AND 255
          ELSE
            modRM = &H84 + ((srcReg AND 7) * 8)
            emitByteCode modRM
            emitByteCode &H24
            emitBytes32 destInfo
          END IF
        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBaseF7
          IF destInfo >= -128 AND destInfo <= 127 THEN
            modRM = &H44 ' reg is 0
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode destInfo AND 255
          ELSE
            modRM = &H84 ' reg is 0
            emitByteCode modRM
            emitByteCode &H24
            emitBytes32 destInfo
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
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase85
          ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
          modRM = &H85 + ((srcReg AND 7) * 8)
          emitByteCode modRM
          emitBytes32 destInfo
        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBaseF7
          ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
          modRM = &H85 ' reg is 0
          emitByteCode modRM
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

    CASE OP_TYPE_MEM_REG
      baseReg = destInfo AND 15

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase85
          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
              emitByteCode modRM
            END IF
          END IF
        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBaseF7
          baseRegMod = baseReg AND 7
          IF baseRegMod = 5 THEN
            modRM = &H40 + baseRegMod ' reg is 0
            emitByteCode modRM
            emitByteCode 0
          ELSE
            IF baseRegMod = 4 THEN
              modRM = &H00 + baseRegMod
              emitByteCode modRM
              emitByteCode &H24
            ELSE
              modRM = &H00 + baseRegMod
              emitByteCode modRM
            END IF
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

    CASE OP_TYPE_MEM_REG_DISP8
      baseReg = destInfo AND 15
      disp8 = (destInfo \ 256) AND 255

      SELECT CASE srcType

        CASE OP_TYPE_REG
          srcReg = srcInfo AND 15
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF srcReg >= 8 THEN rex = rex OR &H4
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBase85
          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
          END IF
        CASE OP_TYPE_IMM
          IF opSizeOrFlag = 64 THEN rex = rex OR &H8
          IF baseReg >= 8 THEN rex = rex OR &H1
          IF rex > 0 THEN emitByteCode &H40 OR rex
          emitByteCode opBaseF7
          baseRegMod = baseReg AND 7
          IF baseRegMod = 4 THEN
            modRM = &H40 + baseRegMod ' reg is 0
            emitByteCode modRM
            emitByteCode &H24
            emitByteCode disp8
          ELSE
            modRM = &H40 + baseRegMod
            emitByteCode modRM
            emitByteCode disp8
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

  END SELECT ' destType

  opTest = tempRet

END FUNCTION ' opTest

''''''''''''''''''''''''
FUNCTION opUnary (passOpCode, passDestType, passDestInfo, passOpSize)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM baseReg AS LONG
  DIM disp AS LONG
  DIM tempRet AS LONG

  tempRet = 0
  rex = 0

  IF passOpSize = 64 THEN rex = rex OR &H08

  SELECT CASE passDestType

    CASE OP_TYPE_REG
      baseReg = passDestInfo
      IF baseReg >= 8 THEN rex = rex OR &H01
      IF passOpSize = 8 AND baseReg >= 4 AND baseReg <= 7 THEN rex = rex OR &H40

      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode &H40 OR rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      modRM = &HC0 + (passOpCode * 8) + (baseReg AND 7)
      emitByteCode modRM

    CASE OP_TYPE_MEM_RIP
      ' RIP-relative has no base register that needs REX.B
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode &H40 OR rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      modRM = (passOpCode * 8) + 5
      emitByteCode modRM
      tempRet = emitPos
      emitBytes32 0

    CASE OP_TYPE_MEM_RSP
      disp = passDestInfo
      ' RSP is register 4, does not need REX.B
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode &H40 OR rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      IF disp >= -128 AND disp <= 127 THEN
        modRM = &H44 + (passOpCode * 8)
        emitByteCode modRM
        emitByteCode &H24 ' SIB
        emitByteCode disp AND 255
      ELSE
        modRM = &H84 + (passOpCode * 8)
        emitByteCode modRM
        emitByteCode &H24 ' SIB
        emitBytes32 disp
      END IF

    CASE OP_TYPE_MEM_RBP
      disp = passDestInfo
      ' RBP is register 5, does not need REX.B
      IF passOpSize = 16 THEN emitByteCode &H66
      IF rex > 0 THEN emitByteCode &H40 OR rex

      IF passOpSize = 8 THEN
        IF passOpCode <= 1 THEN emitByteCode &HFE ELSE emitByteCode &HF6
      ELSE
        IF passOpCode <= 1 THEN emitByteCode &HFF ELSE emitByteCode &HF7
      END IF

      ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
      modRM = &H85 + (passOpCode * 8)
      emitByteCode modRM
      emitBytes32 disp

  END SELECT ' passDestType

  opUnary = tempRet

END FUNCTION ' opUnary

''''''''''''''''''''''''
FUNCTION opXchg (destType, destInfo AS LONG, srcType, srcInfo AS _INTEGER64, opSize)

  DIM rex AS _UNSIGNED _BYTE
  DIM modRM AS _UNSIGNED _BYTE
  DIM destReg AS LONG
  DIM srcReg AS LONG
  DIM baseReg AS LONG
  DIM disp8 AS LONG
  DIM baseRegMod AS LONG
  DIM tempRet AS LONG
  DIM opBase AS LONG

  tempRet = 0
  rex = 0

  IF opSize = 8 THEN opBase = &H86 ELSE opBase = &H87

  IF opSize = 64 THEN rex = rex OR &H08
  IF opSize = 16 THEN emitByteCode &H66

  ' XCHG requires at least one register operand. Immediates are not allowed.
  IF destType <> OP_TYPE_REG AND srcType <> OP_TYPE_REG AND srcType <> OP_TYPE_REG_ALT THEN
    opXchg = 0
    EXIT FUNCTION
  END IF

  IF opSize = 8 THEN
    IF destType = OP_TYPE_REG THEN
      IF destInfo >= 4 AND destInfo <= 7 THEN rex = rex OR &H40
    END IF
    IF srcType = OP_TYPE_REG OR srcType = OP_TYPE_REG_ALT THEN
      IF srcInfo >= 4 AND srcInfo <= 7 THEN rex = rex OR &H40
    END IF
  END IF

  IF destType = OP_TYPE_REG THEN
    destReg = destInfo

    SELECT CASE srcType

      CASE OP_TYPE_REG, OP_TYPE_REG_ALT
        srcReg = srcInfo
        IF destReg >= 8 THEN rex = rex OR &H01 ' REX.B
        IF srcReg >= 8 THEN rex = rex OR &H04 ' REX.R
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        modRM = &HC0 + ((srcReg AND 7) * 8) + (destReg AND 7)
        emitByteCode modRM

      CASE OP_TYPE_MEM_RIP
        IF destReg >= 8 THEN rex = rex OR &H04
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        modRM = ((destReg AND 7) * 8) + 5
        emitByteCode modRM
        tempRet = emitPos
        emitBytes32 0

      CASE OP_TYPE_MEM_RSP
        IF destReg >= 8 THEN rex = rex OR &H04
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        IF srcInfo >= -128 AND srcInfo <= 127 THEN
          modRM = &H44 + ((destReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode srcInfo AND 255
        ELSE
          modRM = &H84 + ((destReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitBytes32 srcInfo
        END IF

      CASE OP_TYPE_MEM_RBP
        IF destReg >= 8 THEN rex = rex OR &H04
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
        modRM = &H85 + ((destReg AND 7) * 8)
        emitByteCode modRM
        emitBytes32 srcInfo

      CASE OP_TYPE_MEM_REG
        baseReg = srcInfo AND 15
        IF destReg >= 8 THEN rex = rex OR &H04
        IF baseReg >= 8 THEN rex = rex OR &H01
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase

        baseRegMod = baseReg AND 7
        IF baseRegMod = 5 THEN
          modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode 0
        ELSE
          IF baseRegMod = 4 THEN
            modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
          ELSE
            modRM = &H00 + ((destReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
          END IF
        END IF

      CASE OP_TYPE_MEM_REG_DISP8
        baseReg = srcInfo AND 15
        disp8 = (srcInfo \ 256) AND 255
        IF destReg >= 8 THEN rex = rex OR &H04
        IF baseReg >= 8 THEN rex = rex OR &H01
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase

        baseRegMod = baseReg AND 7
        IF baseRegMod = 4 THEN
          modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode disp8
        ELSE
          modRM = &H40 + ((destReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode disp8
        END IF

    END SELECT ' srcType

  ELSE
    ' srcType must be the register, destType is the memory location
    srcReg = srcInfo

    SELECT CASE destType

      CASE OP_TYPE_MEM_RIP
        IF srcReg >= 8 THEN rex = rex OR &H04
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        modRM = ((srcReg AND 7) * 8) + 5
        emitByteCode modRM
        tempRet = emitPos
        emitBytes32 0

      CASE OP_TYPE_MEM_RSP
        IF srcReg >= 8 THEN rex = rex OR &H04
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        IF destInfo >= -128 AND destInfo <= 127 THEN
          modRM = &H44 + ((srcReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode destInfo AND 255
        ELSE
          modRM = &H84 + ((srcReg AND 7) * 8)
          emitByteCode modRM
          emitByteCode &H24
          emitBytes32 destInfo
        END IF

      CASE OP_TYPE_MEM_RBP
        IF srcReg >= 8 THEN rex = rex OR &H04
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase
        ' Explicitly bypass disp8 for RBP to maintain consistent instruction length across passes
        modRM = &H85 + ((srcReg AND 7) * 8)
        emitByteCode modRM
        emitBytes32 destInfo

      CASE OP_TYPE_MEM_REG
        baseReg = destInfo AND 15
        IF srcReg >= 8 THEN rex = rex OR &H04
        IF baseReg >= 8 THEN rex = rex OR &H01
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase

        baseRegMod = baseReg AND 7
        IF baseRegMod = 5 THEN
          modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode 0
        ELSE
          IF baseRegMod = 4 THEN
            modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
            emitByteCode &H24
          ELSE
            modRM = &H00 + ((srcReg AND 7) * 8) + baseRegMod
            emitByteCode modRM
          END IF
        END IF

      CASE OP_TYPE_MEM_REG_DISP8
        baseReg = destInfo AND 15
        disp8 = (destInfo \ 256) AND 255
        IF srcReg >= 8 THEN rex = rex OR &H04
        IF baseReg >= 8 THEN rex = rex OR &H01
        IF rex > 0 THEN emitByteCode &H40 OR rex
        emitByteCode opBase

        baseRegMod = baseReg AND 7
        IF baseRegMod = 4 THEN
          modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode &H24
          emitByteCode disp8
        ELSE
          modRM = &H40 + ((srcReg AND 7) * 8) + baseRegMod
          emitByteCode modRM
          emitByteCode disp8
        END IF

    END SELECT ' destType

  END IF

  opXchg = tempRet

END FUNCTION ' opXchg

''''''''''''''''''''''''
FUNCTION parse_BEEP (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2 ' Second returned variable from findInstructionEnd

  ff = verifyNoExtraTokens(endIdx, startIdx, "BEEP")
  IF ff = 0 THEN parse_BEEP = 0: EXIT FUNCTION

  tiraStart

  tiraCall "IAT_BEEP", 2, "800, 250"

  tiraEndAndProcess

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_BEEP = tempSuccess

END FUNCTION ' parse_BEEP

''''''''''''''''''''''''
FUNCTION parse_CASE (startIdx)

  DIM matchPatches(64) AS LONG
  DIM opMode AS LONG
  DIM jmpSkipRHS AS LONG
  DIM jmpMinPos1 AS LONG
  DIM jmpLenPos1 AS LONG
  DIM jmpDonePos1 AS LONG
  DIM jmpMinPos2 AS LONG
  DIM jmpLenPos2 AS LONG
  DIM jmpDonePos2 AS LONG
  DIM jmpMinPos3 AS LONG
  DIM jmpLenPos3 AS LONG
  DIM jmpDonePos3 AS LONG

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "CASE WITHOUT SELECT", ASIS, 0
    parse_CASE = 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_SELECT THEN
    throwCompilerError "CASE NOT INSIDE SELECT", ASIS, 0
    parse_CASE = 0
    EXIT FUNCTION
  END IF

  hiddenVarIdx = ctrls(ctrlCount - 1).SelectVarIdx
  selectType = ctrls(ctrlCount - 1).SelectDataType

  ' If we've already seen a CASE block, emit an unconditional jump to the end of the SELECT
  ' We link this jump into the Patch2 linked list to resolve them all at END SELECT
  IF ctrls(ctrlCount - 1).SelectCaseSeen = 1 THEN
    newJump = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
    patch32 newJump, ctrls(ctrlCount - 1).Patch2
    ctrls(ctrlCount - 1).Patch2 = newJump
  END IF

  ' Resolve the previous CASE's conditional skip jump (if any) to right here
  prevPatch = ctrls(ctrlCount - 1).Patch1
  IF prevPatch <> 0 THEN
    patch32 prevPatch, emitPos - (prevPatch + 4)
    ctrls(ctrlCount - 1).Patch1 = 0
  END IF

  ' Mark that a CASE block has started
  ctrls(ctrlCount - 1).SelectCaseSeen = 1

  ' Check for CASE ELSE
  IF startIdx + 1 <= endIdx THEN
    IF retTokenVal(lineTokens$(startIdx + 1)) = TOK_ELSE THEN
      ' It's CASE ELSE. Execution falls right through. No conditions.
      IF nextStmtIdx <> -1 THEN
        tempSuccess = parseStatement(nextStmtIdx)
      ELSE
        tempSuccess = 1
      END IF
      parse_CASE = tempSuccess
      EXIT FUNCTION
    END IF
  END IF

  matchCount = 0
  exprStart = startIdx + 1

  ' Evaluate a comma-separated list of expressions
  DO WHILE exprStart <= endIdx
    exprEnd = endIdx
    pDepth = 0
    toIdx = -1
    FOR ii = exprStart TO endIdx
      tVal = retTokenVal(lineTokens$(ii))
      IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
      IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
      IF pDepth = 0 THEN
        IF tVal = 256 + ASC(",") THEN
          exprEnd = ii - 1
          EXIT FOR
        END IF
        IF tVal = TOK_TO THEN
          toIdx = ii
        END IF
      END IF
    NEXT

    IF toIdx <> -1 THEN
      '''' Case X to Y

      '''' Evaluate LHS
      exprRes = parseExpression(exprStart, toIdx - 1, 1)
      IF exprRes = 0 THEN parse_CASE = 0: EXIT FUNCTION

      IF selectType = TYPE_DOUBLE THEN
        IF exprIs.DataType = TYPE_STRING THEN
          throwCompilerError "TYPE MISMATCH", ASIS, 0
          parse_CASE = 0
          EXIT FUNCTION
        END IF
        IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
          ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          exprIs.DataType = TYPE_DOUBLE
          exprIsFloat = 2
        END IF
        IF exprIs.DataType = TYPE_SINGLE THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
          exprIs.DataType = TYPE_DOUBLE
          exprIsFloat = 2
        END IF
        ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      ELSE
        IF selectType = TYPE_LONG THEN
          IF exprIs.DataType = TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH", ASIS, 0
            parse_CASE = 0
            EXIT FUNCTION
          END IF
          IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            exprIs.DataType = TYPE_LONG
            exprIsFloat = 0
          END IF
        END IF
      END IF

      ' Move RHS to RBX
      ff = opMov(OP_TYPE_REG, 3, OP_TYPE_REG, 0, 64)

      ' Load SELECT_VAR directly into RAX
      ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, hiddenVarIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_CASE = 0: EXIT FUNCTION

      IF selectType = TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        '''' Inlined string compare
        ff = opMov(OP_TYPE_REG, 6, OP_TYPE_MEM_REG, 0, 64)
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), 64)
        ff = opMov(OP_TYPE_REG, 7, OP_TYPE_MEM_REG, 3, 64)
        ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG_DISP8, 3 + (8 * 256), 64)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
        ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
        jmpMinPos1 = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 2, 64)
        patch8 jmpMinPos1
        ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
        jmpLenPos1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        opPushReg 1
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)
        opFlag FLAG_CLD
        opString STR_CMPS, REP_REP, 8
        opPopReg 1
        jmpDonePos1 = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpLenPos1
        ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
        patch8 jmpDonePos1
        '''' End inlined string compare

        ' If SELECT_VAR < LHS, skip to next comma check
        jmpSkipRHS = opJcc(JCC_JB, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ELSE
        IF selectType = TYPE_DOUBLE THEN
          ' Float compare
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 1, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
          ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 0, OP_TYPE_REG, 1, MODE_SSE_DOUBLE)
          jmpSkipRHS = opJcc(JCC_JB, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ELSE
          ' Numeric compare
          ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
          jmpSkipRHS = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        END IF
      END IF

      '''' Evaluate RHS
      exprRes = parseExpression(toIdx + 1, exprEnd, 1)
      IF exprRes = 0 THEN parse_CASE = 0: EXIT FUNCTION

      IF selectType = TYPE_DOUBLE THEN
        IF exprIs.DataType = TYPE_STRING THEN
          throwCompilerError "TYPE MISMATCH", ASIS, 0
          parse_CASE = 0
          EXIT FUNCTION
        END IF
        IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
          ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          exprIs.DataType = TYPE_DOUBLE
          exprIsFloat = 2
        END IF
        IF exprIs.DataType = TYPE_SINGLE THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
          exprIs.DataType = TYPE_DOUBLE
          exprIsFloat = 2
        END IF
        ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      ELSE
        IF selectType = TYPE_LONG THEN
          IF exprIs.DataType = TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH", ASIS, 0
            parse_CASE = 0
            EXIT FUNCTION
          END IF
          IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            exprIs.DataType = TYPE_LONG
            exprIsFloat = 0
          END IF
        END IF
      END IF

      ' Move RHS to RBX
      ff = opMov(OP_TYPE_REG, 3, OP_TYPE_REG, 0, 64)

      ' Load SELECT_VAR directly into RAX
      ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, hiddenVarIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_CASE = 0: EXIT FUNCTION

      IF selectType = TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        '''' Inlined string compare
        ff = opMov(OP_TYPE_REG, 6, OP_TYPE_MEM_REG, 0, 64)
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), 64)
        ff = opMov(OP_TYPE_REG, 7, OP_TYPE_MEM_REG, 3, 64)
        ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG_DISP8, 3 + (8 * 256), 64)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
        ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
        jmpMinPos2 = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 2, 64)
        patch8 jmpMinPos2
        ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
        jmpLenPos2 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        opPushReg 1
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)
        opFlag FLAG_CLD
        opString STR_CMPS, REP_REP, 8
        opPopReg 1
        jmpDonePos2 = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpLenPos2
        ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
        patch8 jmpDonePos2
        '''' End inlined string compare

        ' If SELECT_VAR <= RHS, matched!
        matchPatches(matchCount) = opJcc(JCC_JBE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
        matchCount = matchCount + 1

      ELSE
        IF selectType = TYPE_DOUBLE THEN
          ' Float compare
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 1, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
          ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 0, OP_TYPE_REG, 1, MODE_SSE_DOUBLE)
          matchPatches(matchCount) = opJcc(JCC_JBE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
          matchCount = matchCount + 1
        ELSE
          ' Numeric compare
          ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
          matchPatches(matchCount) = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
          matchCount = matchCount + 1
        END IF
      END IF

      patch8 jmpSkipRHS

    ELSE
      '''' Case relational / equals

      opType = 0 ' 0:=, 1:<, 2:>, 3:<=, 4:>=, 5:<>
      relStart = exprStart

      IF relStart <= exprEnd THEN
        IF retTokenVal(lineTokens$(relStart)) = 0 THEN
          IF UCASE$(lineTokens$(relStart)) = "IS" THEN
            relStart = relStart + 1
          END IF
        END IF
      END IF

      IF relStart <= exprEnd THEN
        tVal = retTokenVal(lineTokens$(relStart))

        SELECT CASE tVal

          CASE 256 + ASC("=")
            opType = 0
            relStart = relStart + 1
          CASE 256 + ASC("<")
            IF relStart + 1 <= exprEnd THEN
              nxtVal = retTokenVal(lineTokens$(relStart + 1))
              IF nxtVal = 256 + ASC("=") THEN
                opType = 3
                relStart = relStart + 2
              ELSE
                IF nxtVal = 256 + ASC(">") THEN
                  opType = 5
                  relStart = relStart + 2
                ELSE
                  opType = 1
                  relStart = relStart + 1
                END IF
              END IF
            ELSE
              opType = 1
              relStart = relStart + 1
            END IF
          CASE 256 + ASC(">")
            IF relStart + 1 <= exprEnd THEN
              nxtVal = retTokenVal(lineTokens$(relStart + 1))
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

      exprStart = relStart

      exprRes = parseExpression(exprStart, exprEnd, 1)
      IF exprRes = 0 THEN
        parse_CASE = 0
        EXIT FUNCTION
      END IF

      IF selectType = TYPE_DOUBLE THEN
        IF exprIs.DataType = TYPE_STRING THEN
          throwCompilerError "TYPE MISMATCH", ASIS, 0
          parse_CASE = 0
          EXIT FUNCTION
        END IF
        IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
          ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          exprIs.DataType = TYPE_DOUBLE
          exprIsFloat = 2
        END IF
        IF exprIs.DataType = TYPE_SINGLE THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
          exprIs.DataType = TYPE_DOUBLE
          exprIsFloat = 2
        END IF
        ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      ELSE
        IF selectType = TYPE_LONG THEN
          IF exprIs.DataType = TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH", ASIS, 0
            parse_CASE = 0: EXIT FUNCTION
          END IF
          IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_CVTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            exprIs.DataType = TYPE_LONG
            exprIsFloat = 0
          END IF
        END IF
      END IF

      ' Move RHS to RBX
      ff = opMov(OP_TYPE_REG, 3, OP_TYPE_REG, 0, 64)

      ' Load SELECT_VAR directly into RAX
      ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, hiddenVarIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_CASE = 0: EXIT FUNCTION

      IF selectType = TYPE_STRING AND exprIs.DataType = TYPE_STRING THEN
        '''' Inlined string compare
        ff = opMov(OP_TYPE_REG, 6, OP_TYPE_MEM_REG, 0, 64)
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), 64)
        ff = opMov(OP_TYPE_REG, 7, OP_TYPE_MEM_REG, 3, 64)
        ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG_DISP8, 3 + (8 * 256), 64)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
        ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
        jmpMinPos3 = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 2, 64)
        patch8 jmpMinPos3
        ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
        jmpLenPos3 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        opPushReg 1
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)
        opFlag FLAG_CLD
        opString STR_CMPS, REP_REP, 8
        opPopReg 1
        jmpDonePos3 = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpLenPos3
        ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
        patch8 jmpDonePos3
        '''' End inlined string compare

        SELECT CASE opType

          CASE 0: condCode = JCC_JE
          CASE 1: condCode = JCC_JB
          CASE 2: condCode = JCC_JA
          CASE 3: condCode = JCC_JBE
          CASE 4: condCode = JCC_JAE
          CASE 5: condCode = JCC_JNE

        END SELECT ' opType

        matchPatches(matchCount) = opJcc(condCode, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
        matchCount = matchCount + 1

      ELSE
        IF selectType = TYPE_DOUBLE THEN
          ' Float compare
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 1, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
          ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 0, OP_TYPE_REG, 1, MODE_SSE_DOUBLE)

          SELECT CASE opType

            CASE 0: condCode = JCC_JE
            CASE 1: condCode = JCC_JB
            CASE 2: condCode = JCC_JA
            CASE 3: condCode = JCC_JBE
            CASE 4: condCode = JCC_JAE
            CASE 5: condCode = JCC_JNE

          END SELECT ' opType

          matchPatches(matchCount) = opJcc(condCode, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
          matchCount = matchCount + 1
        ELSE
          ' Numeric compare
          ff = opALU(ALU_CMP, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)

          SELECT CASE opType

            CASE 0: condCode = JCC_JE
            CASE 1: condCode = JCC_JL
            CASE 2: condCode = JCC_JG
            CASE 3: condCode = JCC_JLE
            CASE 4: condCode = JCC_JGE
            CASE 5: condCode = JCC_JNE

          END SELECT ' opType

          matchPatches(matchCount) = opJcc(condCode, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
          matchCount = matchCount + 1
        END IF
      END IF

    END IF

    exprStart = exprEnd + 2
  LOOP

  ' If not equal to any of the above comma-separated checks, skip to the next CASE
  skipJump = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
  ctrls(ctrlCount - 1).Patch1 = skipJump

  ' Patch the successful matches to point right here into the execution zone
  FOR ii = 0 TO matchCount - 1
    patch32 matchPatches(ii), emitPos - (matchPatches(ii) + 4)
  NEXT

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_CASE = tempSuccess

END FUNCTION ' parse_CASE

''''''''''''''''''''''''
FUNCTION parse_CLS (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  argStr$ = ""

  tiraStart

  ' Check if there is an argument provided for CLS
  IF endIdx > startIdx THEN
    ' Parse the CLS argument expression into a TIRA variable
    argStr$ = tiraParseExpression$(startIdx + 1, endIdx, ALIM)
    IF argStr$ = "" THEN parse_CLS = 0: EXIT FUNCTION
    ' Ensure the argument is not a string type
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "CLS REQUIRES NUMERIC ARGUMENT", ASIS, 0
      parse_CLS = 0
      EXIT FUNCTION
    END IF
    ' Force the argument to an integer type if it is a float
    argStr$ = tiraForceInt$(argStr$)
  END IF

  ' Handle standard console clearing
  IF compileHasGraphics = 0 THEN
    ' Get the symbol index for the pre-built clear screen string
    clsScratchIdx = resolveSymbol("!CLSSCR$")
    IF clsScratchIdx = -1 THEN parse_CLS = 0: EXIT FUNCTION
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
    ' Assign the address of the clear screen string to the descriptor pointer
    tiraAssign strDesc$, "&!CLSSCR$"

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
    numWrt$ = tiraDimVar$("T", TYPE_INTEGER64)
    ' Use the temporary heap pointer as a safe throwaway memory address
    tiraAssign numWrt$, "!TEMP_HEAP_PTR"
    ' Offset the pointer backwards by eight bytes to ensure safety
    tiraOp TC_SUB, numWrt$, numWrt$, "8"

    ' Create a new jump label for the clearing loop
    loopLbl$ = tiraLabelNew$("CLS_LOOP")
    ' Place the loop label in the TIRA queue
    tiraLabel loopLbl$

    ' Create a variable for the Windows API COORD structure
    coord$ = tiraDimVar$("T", TYPE_LONG)
    ' Shift the Y coordinate to the high word to format the COORD value
    tiraOp TC_MUL, coord$, topVar$, "65536"

    ' Move the console cursor to the current row
    tiraCall "IAT_SETCONSOLECURSORPOSITION", 2, hndVar$ + ", " + coord$
    ' Write the blank spaces to the row
    tiraCall "IAT_WRITEFILE", 5, hndVar$ + ", " + strData$ + ", " + strLen$ + ", " + numWrt$ + ", 0"

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
    skipFb$ = tiraLabelNew$("SKIP_FB")
    ' Jump over framebuffer clearing if type two is requested
    tiraJmpCond "EQ", clsType$, "2", skipFb$

    ' Create a variable for the framebuffer address
    fbPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    ' Retrieve the hardware framebuffer pointer
    tiraNew TC_FRAMEBUF_PTR, fbPtr$

    ' Create a variable for the total pixel count
    fbSize$ = tiraDimVar$("T", TYPE_LONG)
    ' Set the pixel count based on the current graphics configuration
    tiraAssign fbSize$, LTRIM$(STR$(gfxConfig.SizeX * gfxConfig.SizeY))

    ' Zero out the entire framebuffer memory block
    tiraMemSet fbPtr$, "0", fbSize$

    ' Place the skip framebuffer label
    tiraLabel skipFb$

    ' Reset the text cursor X position
    tiraAssign "!GFX_CUR_X", "0"
    ' Reset the text cursor Y position
    tiraAssign "!GFX_CUR_Y", "0"

    ' Create a label to skip clearing the text overlay buffer
    skipTxt$ = tiraLabelNew$("SKIP_TXT")
    ' Jump over text clearing if type one is requested
    tiraJmpCond "EQ", clsType$, "1", skipTxt$

    ' Clear the text buffer by resetting its count to zero
    tiraAssign "!GFX_BUF_COUNT", "0"

    ' Place the skip text buffer label
    tiraLabel skipTxt$

    ' Queue a redraw command to refresh the graphics window
    tiraOp TC_REDRAW, "", "", ""

  END IF

  ' Compile the queued TIRA commands into machine code
  tiraEndAndProcess

  ' Check if there is another statement on this line
  IF nextStmtIdx <> -1 THEN
    ' Parse the next statement recursively
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    ' Mark execution as successful
    tempSuccess = 1
  END IF

  parse_CLS = tempSuccess

END FUNCTION ' parse_CLS

''''''''''''''''''''''''
FUNCTION parse_COLOR (startIdx)

  DIM commaFound AS LONG
  DIM commaPos AS LONG

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  tiraStart

  commaFound = tiraFindComma(startIdx + 1, endIdx)

  IF commaFound = 0 THEN
    ' No comma found, so there is only a foreground argument: COLOR fg
    ' Ensure the statement is not just "COLOR" with no arguments
    IF endIdx >= startIdx + 1 THEN
      hasFg = 1
      fgStr$ = tiraParseExpression$(startIdx + 1, endIdx, ALIM)
    END IF
  ELSE
    ' Comma was found. Check for arguments on either side of it
    commaPos = returnedData2
    IF commaPos > startIdx + 1 THEN
      ' Argument exists before the comma: COLOR fg, ...
      hasFg = 1
      fgStr$ = tiraParseExpression$(startIdx + 1, commaPos - 1, ALIM)
    END IF

    IF commaPos < endIdx THEN
      ' Argument exists after the comma: COLOR ..., bg
      hasBg = 1
      bgStr$ = tiraParseExpression$(commaPos + 1, endIdx, ALIM)
    END IF
  END IF

  ' Process foreground
  IF hasFg = 1 THEN
    IF fgStr$ = "" THEN parse_COLOR = 0: EXIT FUNCTION
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "COLOR REQUIRES NUMERIC", ASIS, 0
      parse_COLOR = 0: EXIT FUNCTION
    END IF
    fgStr$ = tiraForceInt$(fgStr$)

    tiraAssign "!LAST_FG_COLOR", fgStr$
    tiraAssign "!COLOR_INIT", "1"
  ELSE
    ' No foreground was provided, so load the last used one or the default.
    skipInitLbl$ = tiraLabelNew$("SKIP_INIT")
    fgStr$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign fgStr$, "!LAST_FG_COLOR"
    tiraJmpCond "JNE", "!COLOR_INIT", "0", skipInitLbl$
    tiraAssign fgStr$, "7" ' Default FG is 7 (Light Gray) in standard console
    tiraLabel skipInitLbl$
  END IF

  ' Process background
  IF hasBg = 1 THEN
    IF bgStr$ = "" THEN parse_COLOR = 0: EXIT FUNCTION
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "COLOR REQUIRES NUMERIC", ASIS, 0
      parse_COLOR = 0: EXIT FUNCTION
    END IF
    bgStr$ = tiraForceInt$(bgStr$)

    tiraAssign "!LAST_BG_COLOR", bgStr$
  ELSE
    ' No background was provided, so load the last used one.
    bgStr$ = "!LAST_BG_COLOR"
  END IF

  IF compileHasGraphics = 1 THEN
    ' Mask to 0-255 using primitive AND
    fgMask$ = tiraDimVar$("T", TYPE_LONG)
    tiraOp TC_AND, fgMask$, fgStr$, "255"

    ' Extract the pointer to the !GFX_PALETTE$ descriptor
    palDescPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraAssign palDescPtr$, "&!GFX_PALETTE$"

    ' Double-dereference to navigate through the descriptor to the actual string data payload
    palPtr1$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_READ_MEM, palPtr1$ + ", " + palDescPtr$

    palDataAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraNew TC_READ_MEM, palDataAddr$ + ", " + palPtr1$

    ' Offset = mask * 4 (32-bit RGB)
    colorOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_MUL, colorOffset$, fgMask$, "4"

    colorAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, colorAddr$, palDataAddr$, colorOffset$

    ' Extract the final 32-bit color
    actualColor$ = tiraDimVar$("T", TYPE_LONG)
    tiraNew TC_READ_MEM, actualColor$ + ", " + colorAddr$

    ' Write into the target tracking variable
    fgRgbPtr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraAssign fgRgbPtr$, "&!GFX_FG_RGB"

    tiraWriteMem fgRgbPtr$, actualColor$, "4"
  ELSE
    ' Console mode logic: Combine attributes into (BG_MASK) OR (FG_MASK)

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

  tiraEndAndProcess

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_COLOR = tempSuccess

END FUNCTION ' parse_COLOR

''''''''''''''''''''''''
FUNCTION parse_COMMON (startIdx)

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endStmtIdx < startIdx + 2 THEN
    throwCompilerError "MALFORMED COMMON SHARED", ASIS, 0
    parse_COMMON = 0
    EXIT FUNCTION
  END IF

  IF retTokenVal(lineTokens$(startIdx + 1)) <> TOK_SHARED THEN
    throwCompilerError "EXPECTED SHARED AFTER COMMON", ASIS, 0
    parse_COMMON = 0
    EXIT FUNCTION
  END IF

  parse_COMMON = parse_GLOBAL_Core(startIdx + 2, endStmtIdx, nextStmtIdx)

END FUNCTION ' parse_COMMON

''''''''''''''''''''''''
FUNCTION parse_DIM (startIdx)

  DIM pushedDummy AS LONG

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  tokIdx = startIdx + 1
  isShared = 0

  IF tokIdx <= endStmtIdx THEN
    IF retTokenVal(lineTokens$(tokIdx)) = TOK_SHARED THEN
      isShared = 1
      tokIdx = tokIdx + 1
    END IF
  END IF

  IF endStmtIdx < tokIdx THEN
    throwCompilerError "MALFORMED DIM", ASIS, 0
    parse_DIM = 0
    EXIT FUNCTION
  END IF

  DO WHILE tokIdx <= endStmtIdx
    aTok$ = lineTokens$(tokIdx)
    IF retTokenVal(aTok$) <> 0 THEN
      throwCompilerError "EXPECTED IDENTIFIER", ASIS, 0
      parse_DIM = 0
      EXIT FUNCTION
    END IF

    tokIdx = tokIdx + 1

    arrSize1 = 1
    arrSize2 = 0
    isArray = 0

    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
        isArray = 1
        tokIdx = tokIdx + 1

        '''' DIM 1 start
        dimStart = tokIdx
        dimEnd = -1
        pDepth = 0
        FOR ii = tokIdx TO endStmtIdx
          tVal = retTokenVal(lineTokens$(ii))
          IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
          IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
          IF pDepth = 0 AND (tVal = TOK_TO OR tVal = 256 + ASC(",") OR tVal = 256 + ASC(")")) THEN
            dimEnd = ii - 1
            EXIT FOR
          END IF
          IF pDepth = -1 AND tVal = 256 + ASC(")") THEN
            dimEnd = ii - 1
            EXIT FOR
          END IF
        NEXT

        IF dimEnd = -1 THEN
          throwCompilerError "MALFORMED ARRAY DIMENSION", ASIS, 0
          parse_DIM = 0
          EXIT FUNCTION
        END IF

        sizeTok$ = ""
        FOR ii = dimStart TO dimEnd
          tVal = retTokenVal(lineTokens$(ii))

          SELECT CASE tVal

            CASE 0
              sizeTok$ = sizeTok$ + lineTokens$(ii)
            CASE 256 TO 511
              sizeTok$ = sizeTok$ + CHR$(tVal - 256)
            CASE ELSE
              sizeTok$ = sizeTok$ + voc(tVal).text

          END SELECT ' tVal

        NEXT
        sizeTok$ = evalMathConst$(sizeTok$)

        isNum = 1
        FOR i_check = 1 TO LEN(sizeTok$)
          chCheck$ = MID$(sizeTok$, i_check, 1)
          IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN isNum = 0: EXIT FOR
        NEXT
        IF isNum = 0 OR sizeTok$ = "" THEN
          arrSize1 = 0
          isArray = 2
        ELSE
          arrSize1 = VAL(sizeTok$) + 1
          IF defaultArrayDynamic = 1 THEN isArray = 2
        END IF

        tokIdx = dimEnd + 1

        '''' TO clause for DIM 1
        IF tokIdx <= endStmtIdx THEN
          IF retTokenVal(lineTokens$(tokIdx)) = TOK_TO THEN
            tokIdx = tokIdx + 1

            dimStart = tokIdx
            dimEnd = -1
            pDepth = 0
            FOR ii = tokIdx TO endStmtIdx
              tVal = retTokenVal(lineTokens$(ii))
              IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
              IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
              IF pDepth = 0 AND (tVal = 256 + ASC(",") OR tVal = 256 + ASC(")")) THEN
                dimEnd = ii - 1
                EXIT FOR
              END IF
              IF pDepth = -1 AND tVal = 256 + ASC(")") THEN
                dimEnd = ii - 1
                EXIT FOR
              END IF
            NEXT

            IF dimEnd = -1 THEN
              throwCompilerError "MALFORMED UPPER BOUND", ASIS, 0
              parse_DIM = 0
              EXIT FUNCTION
            END IF

            sizeTok$ = ""
            FOR ii = dimStart TO dimEnd
              tVal = retTokenVal(lineTokens$(ii))

              SELECT CASE tVal

                CASE 0
                  sizeTok$ = sizeTok$ + lineTokens$(ii)
                CASE 256 TO 511
                  sizeTok$ = sizeTok$ + CHR$(tVal - 256)
                CASE ELSE
                  sizeTok$ = sizeTok$ + voc(tVal).text

              END SELECT ' tVal

            NEXT
            sizeTok$ = evalMathConst$(sizeTok$)

            isNum = 1
            FOR i_check = 1 TO LEN(sizeTok$)
              chCheck$ = MID$(sizeTok$, i_check, 1)
              IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN isNum = 0: EXIT FOR
            NEXT
            IF isNum = 0 OR sizeTok$ = "" THEN
              arrSize1 = 0
              isArray = 2
            ELSE
              arrSize1 = VAL(sizeTok$) + 1
              IF defaultArrayDynamic = 1 THEN isArray = 2
            END IF
            tokIdx = dimEnd + 1
          END IF
        END IF

        arrSize2 = 0

        '''' DIM 2 start
        IF tokIdx <= endStmtIdx THEN
          IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
            tokIdx = tokIdx + 1

            dimStart = tokIdx
            dimEnd = -1
            pDepth = 0
            FOR ii = tokIdx TO endStmtIdx
              tVal = retTokenVal(lineTokens$(ii))
              IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
              IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
              IF pDepth = 0 AND (tVal = TOK_TO OR tVal = 256 + ASC(")")) THEN
                dimEnd = ii - 1
                EXIT FOR
              END IF
              IF pDepth = -1 AND tVal = 256 + ASC(")") THEN
                dimEnd = ii - 1
                EXIT FOR
              END IF
            NEXT

            IF dimEnd = -1 THEN
              throwCompilerError "MALFORMED SECOND ARRAY SIZE", ASIS, 0
              parse_DIM = 0
              EXIT FUNCTION
            END IF

            sizeTok2$ = ""
            FOR ii = dimStart TO dimEnd
              tVal = retTokenVal(lineTokens$(ii))

              SELECT CASE tVal

                CASE 0
                  sizeTok2$ = sizeTok2$ + lineTokens$(ii)
                CASE 256 TO 511
                  sizeTok2$ = sizeTok2$ + CHR$(tVal - 256)
                CASE ELSE
                  sizeTok2$ = sizeTok2$ + voc(tVal).text

              END SELECT ' tVal

            NEXT
            sizeTok2$ = evalMathConst$(sizeTok2$)

            isNum = 1
            FOR i_check = 1 TO LEN(sizeTok2$)
              chCheck$ = MID$(sizeTok2$, i_check, 1)
              IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN isNum = 0: EXIT FOR
            NEXT
            IF isNum = 0 OR sizeTok2$ = "" THEN
              arrSize2 = 0
              isArray = 2
            ELSE
              arrSize2 = VAL(sizeTok2$) + 1
              IF defaultArrayDynamic = 1 THEN isArray = 2
            END IF
            tokIdx = dimEnd + 1

            '''' TO clause for DIM 2
            IF tokIdx <= endStmtIdx THEN
              IF retTokenVal(lineTokens$(tokIdx)) = TOK_TO THEN
                tokIdx = tokIdx + 1

                dimStart = tokIdx
                dimEnd = -1
                pDepth = 0
                FOR ii = tokIdx TO endStmtIdx
                  tVal = retTokenVal(lineTokens$(ii))
                  IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
                  IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
                  IF pDepth = 0 AND (tVal = 256 + ASC(")")) THEN
                    dimEnd = ii - 1
                    EXIT FOR
                  END IF
                  IF pDepth = -1 AND tVal = 256 + ASC(")") THEN
                    dimEnd = ii - 1
                    EXIT FOR
                  END IF
                NEXT

                IF dimEnd = -1 THEN
                  throwCompilerError "MALFORMED UPPER BOUND", ASIS, 0
                  parse_DIM = 0
                  EXIT FUNCTION
                END IF

                sizeTok2$ = ""
                FOR ii = dimStart TO dimEnd
                  tVal = retTokenVal(lineTokens$(ii))

                  SELECT CASE tVal

                    CASE 0
                      sizeTok2$ = sizeTok2$ + lineTokens$(ii)
                    CASE 256 TO 511
                      sizeTok2$ = sizeTok2$ + CHR$(tVal - 256)
                    CASE ELSE
                      sizeTok2$ = sizeTok2$ + voc(tVal).text

                  END SELECT ' tVal

                NEXT
                sizeTok2$ = evalMathConst$(sizeTok2$)

                isNum = 1
                FOR i_check = 1 TO LEN(sizeTok2$)
                  chCheck$ = MID$(sizeTok2$, i_check, 1)
                  IF (chCheck$ < "0" OR chCheck$ > "9") AND chCheck$ <> "-" AND chCheck$ <> "." THEN isNum = 0: EXIT FOR
                NEXT
                IF isNum = 0 OR sizeTok2$ = "" THEN
                  arrSize2 = 0
                  isArray = 2
                ELSE
                  arrSize2 = VAL(sizeTok2$) + 1
                  IF defaultArrayDynamic = 1 THEN isArray = 2
                END IF
                tokIdx = dimEnd + 1
              END IF
            END IF

          END IF
        END IF

        IF tokIdx > endStmtIdx THEN
          throwCompilerError "EXPECTED )", ASIS, 0
          parse_DIM = 0
          EXIT FUNCTION
        END IF

        IF retTokenVal(lineTokens$(tokIdx)) <> 256 + ASC(")") THEN
          throwCompilerError "EXPECTED )", ASIS, 0
          parse_DIM = 0
          EXIT FUNCTION
        END IF
        tokIdx = tokIdx + 1
      END IF
    END IF

    vName$ = UCASE$(aTok$)
    vIdx = resolveSymbol(vName$)
    IF vIdx = -1 THEN
      parse_DIM = 0
      EXIT FUNCTION
    END IF

    IF symbols(vIdx).IsArray = 1 THEN
      IF isDummyPass = 1 THEN
        throwCompilerError "ARRAY ALREADY DIMMED", ASIS, 0
        parse_DIM = 0
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

    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = TOK_AS THEN
        tokIdx = tokIdx + 1
        IF tokIdx <= endStmtIdx THEN
          IF retTokenVal(lineTokens$(tokIdx)) = TOK_UNSIGNED THEN
            tokIdx = tokIdx + 1
            IF tokIdx <= endStmtIdx THEN
              tType = retTokenVal(lineTokens$(tokIdx))

              SELECT CASE tType

                CASE TOK_BYTE
                  symbols(vIdx).DataType = TYPE_UBYTE
                  tokIdx = tokIdx + 1
                CASE TOK_INTEGER
                  symbols(vIdx).DataType = TYPE_UINTEGER
                  tokIdx = tokIdx + 1
                CASE TOK_INTEGER64
                  symbols(vIdx).DataType = TYPE_UINT64
                  tokIdx = tokIdx + 1
                CASE TOK_LONG
                  symbols(vIdx).DataType = TYPE_ULONG
                  tokIdx = tokIdx + 1
                CASE ELSE
                  throwCompilerError "EXPECTED BYTE, INTEGER, LONG, OR INTEGER64 BUT GOT " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                  parse_DIM = 0
                  EXIT FUNCTION

              END SELECT ' tType

            ELSE
              throwCompilerError "EXPECTED TYPE AFTER _UNSIGNED", ASIS, 0
              parse_DIM = 0
              EXIT FUNCTION
            END IF
          ELSE
            tType = retTokenVal(lineTokens$(tokIdx))

            SELECT CASE tType

              CASE 0 ' UDT Identifier Match
                uTok$ = UCASE$(lineTokens$(tokIdx))
                matchedUdt = -1
                FOR iUdt = 0 TO udtCount - 1
                  IF RTRIM$(udts(iUdt).RecordName) = uTok$ THEN
                    matchedUdt = iUdt
                    EXIT FOR
                  END IF
                NEXT
                IF matchedUdt <> -1 THEN
                  symbols(vIdx).DataType = TYPE_UDT
                  symbols(vIdx).UDTIndex = matchedUdt
                  tokIdx = tokIdx + 1
                ELSE
                  throwCompilerError "UNSUPPORTED TYPE OR UNKNOWN UDT " + CHR$(34) + lineTokens$(tokIdx) + CHR$(34), ASIS, 0
                  parse_DIM = 0
                  EXIT FUNCTION
                END IF
              CASE TOK_BYTE
                symbols(vIdx).DataType = TYPE_BYTE
                tokIdx = tokIdx + 1
              CASE TOK_DOUBLE
                symbols(vIdx).DataType = TYPE_DOUBLE
                tokIdx = tokIdx + 1
              CASE TOK_INTEGER
                symbols(vIdx).DataType = TYPE_INTEGER
                tokIdx = tokIdx + 1
              CASE TOK_INTEGER64
                symbols(vIdx).DataType = TYPE_INTEGER64
                tokIdx = tokIdx + 1
              CASE TOK_LONG
                symbols(vIdx).DataType = TYPE_LONG
                tokIdx = tokIdx + 1
              CASE TOK_SINGLE
                symbols(vIdx).DataType = TYPE_SINGLE
                tokIdx = tokIdx + 1
              CASE TOK_DSTRING
                symbols(vIdx).DataType = TYPE_STRING
                tokIdx = tokIdx + 1
                IF tokIdx <= endStmtIdx THEN
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("*") THEN
                    throwCompilerError "DSTRING CANNOT HAVE * LENGTH", ASIS, 0
                    parse_DIM = 0
                    EXIT FUNCTION
                  END IF
                END IF
              CASE TOK_STRING
                symbols(vIdx).DataType = TYPE_STRING
                tokIdx = tokIdx + 1
                IF tokIdx <= endStmtIdx THEN
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("*") THEN
                    tokIdx = tokIdx + 1
                    IF tokIdx <= endStmtIdx THEN
                      sizeTok$ = lineTokens$(tokIdx)
                      isNum = 1
                      FOR i_check = 1 TO LEN(sizeTok$)
                        chCheck$ = MID$(sizeTok$, i_check, 1)
                        IF chCheck$ < "0" OR chCheck$ > "9" THEN isNum = 0: EXIT FOR
                      NEXT
                      IF isNum = 0 THEN
                        throwCompilerError "STRING LENGTH MUST BE CONSTANT", ASIS, 0
                        parse_DIM = 0
                        EXIT FUNCTION
                      END IF

                      fixedLen = VAL(sizeTok$)
                      lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
                      floatVarData(lenIdx) = fixedLen
                      strVarData$(vIdx) = SPACE$(fixedLen)

                      tokIdx = tokIdx + 1
                    ELSE
                      throwCompilerError "EXPECTED STRING LENGTH", ASIS, 0
                      parse_DIM = 0
                      EXIT FUNCTION
                    END IF
                  ELSE
                    throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                    parse_DIM = 0
                    EXIT FUNCTION
                  END IF
                ELSE
                  throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                  parse_DIM = 0
                  EXIT FUNCTION
                END IF
              CASE ELSE
                throwCompilerError "UNSUPPORTED TYPE " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                parse_DIM = 0
                EXIT FUNCTION

            END SELECT ' tType

          END IF
        ELSE
          throwCompilerError "EXPECTED TYPE AFTER AS", ASIS, 0
          parse_DIM = 0
          EXIT FUNCTION
        END IF
      END IF
    END IF

    axIdx = resolveSymbol("!" + vName$ + "_AX")
    ayIdx = resolveSymbol("!" + vName$ + "_AY")

    ' Initialize AX (Stride X)
    pushedDummy = 0
    IF updateStackAlignment = 1 THEN opPushReg 13: pushedDummy = 1
    opPushReg 12
    ff = opMov(OP_TYPE_REG, 12, OP_TYPE_IMM, arrSize1, MODE_IMM64)
    ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 12, 64, axIdx)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_DIM = 0: EXIT FUNCTION
    opPopReg 12
    IF pushedDummy = 1 THEN opPopReg 13

    ' Initialize AY (Stride Y)
    pushedDummy = 0
    IF updateStackAlignment = 1 THEN opPushReg 13: pushedDummy = 1
    opPushReg 12
    ff = opMov(OP_TYPE_REG, 12, OP_TYPE_IMM, arrSize2, MODE_IMM64)
    ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 12, 64, ayIdx)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_DIM = 0: EXIT FUNCTION
    opPopReg 12
    IF pushedDummy = 1 THEN opPopReg 13

    IF defaultArrayDynamic = 1 AND arrSize1 > 0 THEN
      dt = symbols(vIdx).DataType
      elemSize = 8

      SELECT CASE dt

        CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
        CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
        CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
        CASE TYPE_STRING
          lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
          IF floatVarData(lenIdx) > 0 THEN
            elemSize = floatVarData(lenIdx)
          ELSE
            elemSize = 8
          END IF
        CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize

      END SELECT ' dt

      totalElems = arrSize1
      IF arrSize2 > 0 THEN totalElems = arrSize1 * arrSize2

      allocSize = totalElems * elemSize

      emitDeepFreeArray vIdx
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_DIM = 0: EXIT FUNCTION

      ' Allocate new array memory block
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, allocSize, 64)

      opPushReg 13
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_REG, 4, 64)
      ff = opALU(ALU_AND, OP_TYPE_REG, 4, OP_TYPE_IMM, -16, 64)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)

      ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32) ' HEAP_ZERO_MEMORY
      ff = opCall(IAT_HEAPALLOC, CALLMODE_IAT)

      ff = opMov(OP_TYPE_REG, 4, OP_TYPE_REG, 13, 64)
      opPopReg 13

      ' Store pointer into the array root variable slot
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, vIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_DIM = 0: EXIT FUNCTION
    END IF

    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
        tokIdx = tokIdx + 1
      ELSE
        throwCompilerError "UNEXPECTED TOKEN AFTER DIM", ASIS, 0
        parse_DIM = 0
        EXIT FUNCTION
      END IF
    END IF
  LOOP

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_DIM = tempSuccess

END FUNCTION ' parse_DIM

''''''''''''''''''''''''
FUNCTION parse_DO (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  hasCond = 0

  IF endIdx > startIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx + 1))
    IF tVal = TOK_UNTIL THEN
      hasCond = 1
    ELSE
      throwCompilerError "EXPECTED UNTIL", ASIS, 0
      parse_DO = 0
      EXIT FUNCTION
    END IF
  END IF

  loopTop = emitPos
  jmpExitPos = 0

  IF hasCond = 1 THEN
    truePatchCount = 0
    falsePatchCount = 0

    condRes = parseCondition(startIdx + 2, endIdx, 1, 0)
    IF condRes = 0 THEN
      parse_DO = 0
      EXIT FUNCTION
    END IF

    IF truePatchCount > 1 THEN
      jmpFalsePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      FOR ii = 0 TO truePatchCount - 1
        patch32 truePatches(ii), emitPos - (truePatches(ii) + 4)
      NEXT
      unifiedTruePatch = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
      patch8 jmpFalsePos
      truePatches(0) = unifiedTruePatch
      truePatchCount = 1
    END IF

    jmpExitPos = truePatches(0)

    FOR ii = 0 TO falsePatchCount - 1
      patch32 falsePatches(ii), emitPos - (falsePatches(ii) + 4)
    NEXT
  END IF

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    parse_DO = 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_DO
  ctrls(ctrlCount).Patch1 = loopTop
  ctrls(ctrlCount).Patch2 = jmpExitPos
  ctrlCount = ctrlCount + 1

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_DO = tempSuccess

END FUNCTION ' parse_DO

''''''''''''''''''''''''
FUNCTION parse_END (startIdx)

  DIM vIdx AS LONG
  DIM subIdx AS LONG

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  isBlockEnd = 0
  IF endStmtIdx > startIdx THEN
    tok2 = retTokenVal(lineTokens$(startIdx + 1))
    IF tok2 = TOK_SUB OR tok2 = TOK_FUNCTION THEN isBlockEnd = 1
    IF tok2 = TOK_IF THEN isBlockEnd = 1
    IF tok2 = TOK_SELECT THEN isBlockEnd = 1
  END IF

  IF isBlockEnd = 1 THEN
    tok2 = retTokenVal(lineTokens$(startIdx + 1))
    IF tok2 = TOK_SUB OR tok2 = TOK_FUNCTION THEN
      IF tok2 = TOK_SUB AND insideSub <> 1 THEN
        throwCompilerError "END SUB WITHOUT SUB", ASIS, 0
        parse_END = 0
        EXIT FUNCTION
      END IF
      IF tok2 = TOK_FUNCTION AND insideSub <> 2 THEN
        throwCompilerError "FUNCTION END WITHOUT FUNCTION", ASIS, 0
        parse_END = 0
        EXIT FUNCTION
      END IF

      ' Resolve all early EXIT SUB / EXIT FUNCTION jumps to land here
      vIdx = resolveSymbol(currentSubName$)
      IF vIdx <> -1 THEN
        subIdx = symbols(vIdx).SubIndex
        IF subIdx <> -1 THEN
          currentPatch = subs(subIdx).ExitPatchList
          DO WHILE currentPatch <> 0
            b1 = intermediateCode(currentPatch)
            b2 = intermediateCode(currentPatch + 1)
            b3 = intermediateCode(currentPatch + 2)
            b4 = intermediateCode(currentPatch + 3)

            prevPatch = b1
            prevPatch = prevPatch + (b2 * 256)
            prevPatch = prevPatch + (b3 * 65536)
            IF b4 > 0 THEN prevPatch = prevPatch + (b4 * 16777216)

            patch32 currentPatch, emitPos - (currentPatch + 4)
            currentPatch = prevPatch
          LOOP
        END IF
      END IF

      ' Restore stack alignment, pop ABI non-volatile registers, and return
      emitSubEpilogue

      ' Patch the jump over the SUB/FUNCTION
      IF subIdx <> -1 THEN
        patch32 subs(subIdx).JmpPatchPos, emitPos - (subs(subIdx).JmpPatchPos + 4)
      END IF

      currentScopeID = 0
      insideSub = 0
      currentSubName$ = ""
      IF nextStmtIdx <> -1 THEN
        tempSuccess = parseStatement(nextStmtIdx)
      ELSE
        tempSuccess = 1
      END IF
      parse_END = tempSuccess
      EXIT FUNCTION
    END IF

    IF tok2 = TOK_IF THEN
      IF ctrlCount = 0 THEN
        throwCompilerError "END IF WITHOUT IF", ASIS, 0
        parse_END = 0
        EXIT FUNCTION
      END IF
      ctrlCount = ctrlCount - 1
      IF ctrls(ctrlCount).Type = CTRL_IF OR ctrls(ctrlCount).Type = CTRL_ELSE THEN
        ' Resolve the false condition jump from the last IF block (if no ELSE block)
        prevPatch = ctrls(ctrlCount).Patch1
        IF prevPatch <> 0 THEN
          patch32 prevPatch, emitPos - (prevPatch + 4)
        END IF

        ' Walk the Patch2 linked list and resolve all successful block exit jumps to land here
        currentPatch = ctrls(ctrlCount).Patch2
        DO WHILE currentPatch <> 0
          b1 = intermediateCode(currentPatch)
          b2 = intermediateCode(currentPatch + 1)
          b3 = intermediateCode(currentPatch + 2)
          b4 = intermediateCode(currentPatch + 3)

          prevPatch = b1
          prevPatch = prevPatch + (b2 * 256)
          prevPatch = prevPatch + (b3 * 65536)
          IF b4 > 0 THEN prevPatch = prevPatch + (b4 * 16777216)

          patch32 currentPatch, emitPos - (currentPatch + 4)
          currentPatch = prevPatch
        LOOP
      ELSE
        throwCompilerError "END IF MISMATCH", ASIS, 0
        parse_END = 0
        EXIT FUNCTION
      END IF

      IF nextStmtIdx <> -1 THEN
        tempSuccess = parseStatement(nextStmtIdx)
      ELSE
        tempSuccess = 1
      END IF
      parse_END = tempSuccess
      EXIT FUNCTION
    END IF

    IF tok2 = TOK_SELECT THEN
      IF ctrlCount = 0 THEN
        throwCompilerError "END SELECT WITHOUT SELECT", ASIS, 0
        parse_END = 0
        EXIT FUNCTION
      END IF

      ctrlCount = ctrlCount - 1

      IF ctrls(ctrlCount).Type = CTRL_SELECT THEN
        ' If the final CASE block condition failed, its bypass patch ends here
        prevPatch = ctrls(ctrlCount).Patch1
        IF prevPatch <> 0 THEN
          patch32 prevPatch, emitPos - (prevPatch + 4)
        END IF

        ' Walk backward to resolve the linked list of successful CASE exit jumps
        currentPatch = ctrls(ctrlCount).Patch2
        DO WHILE currentPatch <> 0
          b1 = intermediateCode(currentPatch)
          b2 = intermediateCode(currentPatch + 1)
          b3 = intermediateCode(currentPatch + 2)
          b4 = intermediateCode(currentPatch + 3)

          prevPatch = b1
          prevPatch = prevPatch + (b2 * 256)
          prevPatch = prevPatch + (b3 * 65536)
          IF b4 > 0 THEN prevPatch = prevPatch + (b4 * 16777216)

          patch32 currentPatch, emitPos - (currentPatch + 4)
          currentPatch = prevPatch
        LOOP

      ELSE
        throwCompilerError "END SELECT MISMATCH", ASIS, 0
        parse_END = 0
        EXIT FUNCTION
      END IF

      IF nextStmtIdx <> -1 THEN
        tempSuccess = parseStatement(nextStmtIdx)
      ELSE
        tempSuccess = 1
      END IF
      parse_END = tempSuccess
      EXIT FUNCTION
    END IF
  END IF

  ' Standalone END with optional return code
  IF endStmtIdx > startIdx THEN
    exprRes = parseExpression(startIdx + 1, endStmtIdx, ALIM)
    IF exprRes = 0 THEN parse_END = 0: EXIT FUNCTION

    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "END REQUIRES NUMERIC", ASIS, 0
      parse_END = 0
      EXIT FUNCTION
    END IF

    ' Ensure float gets cast to integer natively
    ff = genCastExprToInt(0)

    ' Store directly into !EXIT_CODE
    vIdxExit = resolveSymbol("!EXIT_CODE")
    IF vIdxExit <> -1 THEN
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, vIdxExit)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_END = 0: EXIT FUNCTION
    END IF
  END IF

  ' Jump to the end of the program
  vIdxProg = resolveSymbol("&END_PROGRAM")
  IF vIdxProg <> -1 THEN
    addPatch PATCH_GOTO, opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdxProg, 0
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_END = 0: EXIT FUNCTION
  END IF

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_END = tempSuccess

END FUNCTION ' parse_END

''''''''''''''''''''''''
FUNCTION parse_EXIT (startIdx)

  DIM vIdx AS LONG
  DIM subIdx AS LONG

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endStmtIdx < startIdx + 1 THEN
    throwCompilerError "EXPECTED SUB OR FUNCTION", ASIS, 0
    parse_EXIT = 0
    EXIT FUNCTION
  END IF

  tok2 = retTokenVal(lineTokens$(startIdx + 1))
  IF tok2 = TOK_SUB OR tok2 = TOK_FUNCTION THEN
    IF tok2 = TOK_SUB AND insideSub <> 1 THEN
      throwCompilerError "EXIT SUB OUTSIDE SUB", ASIS, 0
      parse_EXIT = 0
      EXIT FUNCTION
    END IF
    IF tok2 = TOK_FUNCTION AND insideSub <> 2 THEN
      throwCompilerError "EXIT FUNCTION OUTSIDE FUNCTION", ASIS, 0
      parse_EXIT = 0
      EXIT FUNCTION
    END IF

    ' Route control flow to the true epilogue using a forward jump
    vIdx = resolveSymbol(currentSubName$)
    IF vIdx <> -1 THEN
      subIdx = symbols(vIdx).SubIndex
      IF subIdx <> -1 THEN
        genTempHeapReset

        jmpExit = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
        patch32 jmpExit, subs(subIdx).ExitPatchList
        subs(subIdx).ExitPatchList = jmpExit
      END IF
    END IF
  ELSE
    IF tok2 = TOK_DO THEN
      foundCtrl = -1
      FOR cIdx = ctrlCount - 1 TO 0 STEP -1
        IF ctrls(cIdx).Type = CTRL_DO THEN
          foundCtrl = cIdx
          EXIT FOR
        END IF
      NEXT

      IF foundCtrl = -1 THEN
        throwCompilerError "EXIT DO OUTSIDE DO LOOP", ASIS, 0
        parse_EXIT = 0
        EXIT FUNCTION
      END IF

      genTempHeapReset

      jmpExit = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
      patch32 jmpExit, ctrls(foundCtrl).Patch2
      ctrls(foundCtrl).Patch2 = jmpExit
    ELSE
      IF tok2 = TOK_FOR THEN
        foundCtrl = -1
        FOR cIdx = ctrlCount - 1 TO 0 STEP -1
          IF ctrls(cIdx).Type = CTRL_FOR THEN
            foundCtrl = cIdx
            EXIT FOR
          END IF
        NEXT

        IF foundCtrl = -1 THEN
          throwCompilerError "EXIT FOR OUTSIDE FOR LOOP", ASIS, 0
          parse_EXIT = 0
          EXIT FUNCTION
        END IF

        genTempHeapReset

        jmpExit = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
        patch32 jmpExit, ctrls(foundCtrl).Patch3
        ctrls(foundCtrl).Patch3 = jmpExit
      ELSE
        throwCompilerError "UNRECOGNIZED EXIT", ASIS, 0
        parse_EXIT = 0
        EXIT FUNCTION
      END IF
    END IF
  END IF

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_EXIT = tempSuccess

END FUNCTION ' parse_EXIT

''''''''''''''''''''''''
FUNCTION parse_FOR (startIdx)

  DIM exprRes AS LONG

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endIdx < startIdx + 3 THEN
    throwCompilerError "MALFORMED FOR", ASIS, 0
    parse_FOR = 0
    EXIT FUNCTION
  END IF

  vTok$ = lineTokens$(startIdx + 1)
  IF retTokenVal(vTok$) <> 0 OR RIGHT$(vTok$, 1) = "$" THEN
    throwCompilerError "FOR NEEDS NUMERIC VAR", ASIS, 0
    parse_FOR = 0
    EXIT FUNCTION
  END IF

  vName$ = UCASE$(vTok$)
  IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
  vIdx = resolveSymbol(vName$)
  IF vIdx = -1 THEN
    parse_FOR = 0
    EXIT FUNCTION
  END IF

  IF retTokenVal(lineTokens$(startIdx + 2)) <> 256 + ASC("=") THEN
    throwCompilerError "FOR MISSING =", ASIS, 0
    parse_FOR = 0
    EXIT FUNCTION
  END IF

  toIdx = -1
  stepIdx = -1
  FOR ii = startIdx + 3 TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = TOK_TO THEN toIdx = ii
    IF tVal = TOK_STEP THEN stepIdx = ii
  NEXT

  IF toIdx = -1 THEN
    throwCompilerError "FOR MISSING TO", ASIS, 0
    parse_FOR = 0
    EXIT FUNCTION
  END IF

  IF toIdx <= startIdx + 2 THEN
    throwCompilerError "FOR MISSING START EXPR", ASIS, 0
    parse_FOR = 0
    EXIT FUNCTION
  END IF

  IF stepIdx <> -1 THEN
    IF stepIdx <= toIdx + 1 THEN
      throwCompilerError "FOR MISSING END EXPR", ASIS, 0
      parse_FOR = 0
      EXIT FUNCTION
    END IF
    IF stepIdx = endIdx THEN
      throwCompilerError "FOR MISSING STEP EXPR", ASIS, 0
      parse_FOR = 0
      EXIT FUNCTION
    END IF
  ELSE
    IF toIdx = endIdx THEN
      throwCompilerError "FOR MISSING END EXPR", ASIS, 0
      parse_FOR = 0
      EXIT FUNCTION
    END IF
  END IF

  tiraStart

  '''' Evaluate Start Value
  IF compileClassicMode = 1 THEN expectedSymType = symbols(vIdx).DataType
  startVar$ = tiraParseExpression$(startIdx + 3, toIdx - 1, 0)
  IF startVar$ = "" THEN parse_FOR = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "FOR NEEDS NUMERIC", ASIS, 0
    parse_FOR = 0: EXIT FUNCTION
  END IF

  endExprEnd = endIdx
  IF stepIdx <> -1 THEN endExprEnd = stepIdx - 1

  endName$ = "!FOR_END_" + cTrNum$(ctrlCount)
  endVarIdx = resolveSymbol(endName$)
  IF endVarIdx = -1 THEN
    parse_FOR = 0
    EXIT FUNCTION
  END IF
  symbols(endVarIdx).DataType = symbols(vIdx).DataType

  '''' Evaluate End Value
  IF compileClassicMode = 1 THEN expectedSymType = symbols(vIdx).DataType
  endVar$ = tiraParseExpression$(toIdx + 1, endExprEnd, 0)
  IF endVar$ = "" THEN parse_FOR = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "FOR NEEDS NUMERIC", ASIS, 0
    parse_FOR = 0: EXIT FUNCTION
  END IF

  stepName$ = "!FOR_STEP_" + cTrNum$(ctrlCount)
  stepVarIdx = resolveSymbol(stepName$)
  IF stepVarIdx = -1 THEN
    parse_FOR = 0
    EXIT FUNCTION
  END IF
  symbols(stepVarIdx).DataType = symbols(vIdx).DataType

  '''' Evaluate Step Value
  IF stepIdx <> -1 THEN
    IF compileClassicMode = 1 THEN expectedSymType = symbols(vIdx).DataType
    stepVar$ = tiraParseExpression$(stepIdx + 1, endIdx, 0)
    IF stepVar$ = "" THEN parse_FOR = 0: EXIT FUNCTION
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "FOR NEEDS NUMERIC", ASIS, 0
      parse_FOR = 0: EXIT FUNCTION
    END IF
  ELSE
    stepVar$ = "1"
  END IF

  vNameTira$ = RTRIM$(symbols(vIdx).RecordName)

  tiraAssign vNameTira$, startVar$
  tiraAssign endName$, endVar$
  tiraAssign stepName$, stepVar$

  lblTop$ = "&FOR_TOP_" + cTrNum$(ctrlCount)
  lblCond$ = "&FOR_COND_" + cTrNum$(ctrlCount)

  tiraJmp lblCond$
  tiraLabel lblTop$

  tiraEndAndProcess

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    parse_FOR = 0: EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_FOR
  ctrls(ctrlCount).ForVarIdx = vIdx
  ctrls(ctrlCount).ForEndVarIdx = endVarIdx
  ctrls(ctrlCount).ForStepVarIdx = stepVarIdx
  ctrls(ctrlCount).Patch1 = 0 ' TIRA handles jumps natively via labels
  ctrls(ctrlCount).Patch2 = 0
  ctrls(ctrlCount).Patch3 = 0 ' Initialize EXIT FOR linked list
  ctrlCount = ctrlCount + 1

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_FOR = tempSuccess

END FUNCTION ' parse_FOR

''''''''''''''''''''''''
FUNCTION parse_GLOBAL (startIdx)

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endStmtIdx < startIdx + 1 THEN
    throwCompilerError "MALFORMED GLOBAL", ASIS, 0
    parse_GLOBAL = 0
    EXIT FUNCTION
  END IF

  parse_GLOBAL = parse_GLOBAL_Core(startIdx + 1, endStmtIdx, nextStmtIdx)

END FUNCTION ' parse_GLOBAL

''''''''''''''''''''''''
FUNCTION parse_GLOBAL_Core (startTokIdx, endStmtIdx, nextStmtIdx)

  ' Used by the synonym commands GLOBAL and PARSE SHARED

  tempSuccess = 0
  tokIdx = startTokIdx

  DO WHILE tokIdx <= endStmtIdx
    vTok$ = lineTokens$(tokIdx)
    IF retTokenVal(vTok$) <> 0 THEN
      throwCompilerError "EXPECTED VARIABLE NAME", ASIS, 0
      parse_GLOBAL_Core = 0
      EXIT FUNCTION
    END IF

    vName$ = UCASE$(vTok$)
    vIdx = resolveSymbol(vName$)
    IF vIdx = -1 THEN
      parse_GLOBAL_Core = 0
      EXIT FUNCTION
    END IF

    symbols(vIdx).IsShared = 1
    symbols(vIdx).IsExplicit = 1

    tokIdx = tokIdx + 1

    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = TOK_AS THEN
        tokIdx = tokIdx + 1
        IF tokIdx <= endStmtIdx THEN
          IF retTokenVal(lineTokens$(tokIdx)) = TOK_UNSIGNED THEN
            tokIdx = tokIdx + 1
            IF tokIdx <= endStmtIdx THEN
              tType = retTokenVal(lineTokens$(tokIdx))

              SELECT CASE tType

                CASE TOK_BYTE
                  symbols(vIdx).DataType = TYPE_UBYTE
                  tokIdx = tokIdx + 1
                CASE TOK_INTEGER
                  symbols(vIdx).DataType = TYPE_UINTEGER
                  tokIdx = tokIdx + 1
                CASE TOK_INTEGER64
                  symbols(vIdx).DataType = TYPE_UINT64
                  tokIdx = tokIdx + 1
                CASE TOK_LONG
                  symbols(vIdx).DataType = TYPE_ULONG
                  tokIdx = tokIdx + 1
                CASE ELSE
                  throwCompilerError "EXPECTED BYTE, INTEGER, LONG, OR INTEGER64 BUT GOT " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                  parse_GLOBAL_Core = 0
                  EXIT FUNCTION

              END SELECT ' tType

            ELSE
              throwCompilerError "EXPECTED TYPE AFTER _UNSIGNED", ASIS, 0
              parse_GLOBAL_Core = 0
              EXIT FUNCTION
            END IF
          ELSE
            tType = retTokenVal(lineTokens$(tokIdx))

            SELECT CASE tType

              CASE 0 ' UDT Identifier Match
                uTok$ = UCASE$(lineTokens$(tokIdx))
                matchedUdt = -1
                FOR iUdt = 0 TO udtCount - 1
                  IF RTRIM$(udts(iUdt).RecordName) = uTok$ THEN
                    matchedUdt = iUdt
                    EXIT FOR
                  END IF
                NEXT
                IF matchedUdt <> -1 THEN
                  symbols(vIdx).DataType = TYPE_UDT
                  symbols(vIdx).UDTIndex = matchedUdt
                  tokIdx = tokIdx + 1
                ELSE
                  throwCompilerError "UNSUPPORTED TYPE OR UNKNOWN UDT " + CHR$(34) + lineTokens$(tokIdx) + CHR$(34), ASIS, 0
                  parse_GLOBAL_Core = 0
                  EXIT FUNCTION
                END IF
              CASE TOK_BYTE
                symbols(vIdx).DataType = TYPE_BYTE
                tokIdx = tokIdx + 1
              CASE TOK_DOUBLE
                symbols(vIdx).DataType = TYPE_DOUBLE
                tokIdx = tokIdx + 1
              CASE TOK_INTEGER
                symbols(vIdx).DataType = TYPE_INTEGER
                tokIdx = tokIdx + 1
              CASE TOK_INTEGER64
                symbols(vIdx).DataType = TYPE_INTEGER64
                tokIdx = tokIdx + 1
              CASE TOK_LONG
                symbols(vIdx).DataType = TYPE_LONG
                tokIdx = tokIdx + 1
              CASE TOK_SINGLE
                symbols(vIdx).DataType = TYPE_SINGLE
                tokIdx = tokIdx + 1
              CASE TOK_DSTRING
                symbols(vIdx).DataType = TYPE_STRING
                tokIdx = tokIdx + 1
                IF tokIdx <= endStmtIdx THEN
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("*") THEN
                    throwCompilerError "DSTRING CANNOT HAVE * LENGTH", ASIS, 0
                    parse_GLOBAL_Core = 0
                    EXIT FUNCTION
                  END IF
                END IF
              CASE TOK_STRING
                symbols(vIdx).DataType = TYPE_STRING
                tokIdx = tokIdx + 1
                IF tokIdx <= endStmtIdx THEN
                  IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("*") THEN
                    tokIdx = tokIdx + 1
                    IF tokIdx <= endStmtIdx THEN
                      sizeTok$ = lineTokens$(tokIdx)
                      isNum = 1
                      FOR i_check = 1 TO LEN(sizeTok$)
                        chCheck$ = MID$(sizeTok$, i_check, 1)
                        IF chCheck$ < "0" OR chCheck$ > "9" THEN isNum = 0: EXIT FOR
                      NEXT
                      IF isNum = 0 THEN
                        throwCompilerError "STRING LENGTH MUST BE CONSTANT", ASIS, 0
                        parse_GLOBAL_Core = 0
                        EXIT FUNCTION
                      END IF

                      fixedLen = VAL(sizeTok$)
                      lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
                      floatVarData(lenIdx) = fixedLen
                      strVarData$(vIdx) = SPACE$(fixedLen)

                      tokIdx = tokIdx + 1
                    ELSE
                      throwCompilerError "EXPECTED STRING LENGTH", ASIS, 0
                      parse_GLOBAL_Core = 0
                      EXIT FUNCTION
                    END IF
                  ELSE
                    throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                    parse_GLOBAL_Core = 0
                    EXIT FUNCTION
                  END IF
                ELSE
                  throwCompilerError "STRING REQUIRES * LENGTH (USE DSTRING FOR DYNAMIC)", ASIS, 0
                  parse_GLOBAL_Core = 0
                  EXIT FUNCTION
                END IF
              CASE ELSE
                throwCompilerError "UNSUPPORTED TYPE " + CHR$(34) + retTokenText$(lineTokens$(tokIdx)) + CHR$(34), ASIS, 0
                parse_GLOBAL_Core = 0
                EXIT FUNCTION

            END SELECT ' tType

          END IF
        ELSE
          throwCompilerError "EXPECTED TYPE AFTER AS", ASIS, 0
          parse_GLOBAL_Core = 0
          EXIT FUNCTION
        END IF
      END IF
    END IF

    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
        tokIdx = tokIdx + 1
      ELSE
        throwCompilerError "EXPECTED COMMA", ASIS, 0
        parse_GLOBAL_Core = 0
        EXIT FUNCTION
      END IF
    END IF
  LOOP

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_GLOBAL_Core = tempSuccess

END FUNCTION ' parse_GLOBAL_core

''''''''''''''''''''''''
FUNCTION parse_GOTO (startIdx)

  ' Here is the current, active prefix system:

  ' ! (Exclamation Mark): You are correct. This is used for Global
  ' compiler/parser state variables. These are internal variables that the
  ' compiler itself uses to manage its state during compilation or that the
  '  final executable uses at runtime for its own internal tracking.
  ' Examples from the code: !GFX_CUR_X, !TEMP_HEAP_PTR, !CRLF$

  ' & (Ampersand): This is for Addresses and Jump Labels. These
  ' are generated internally by the compiler to mark specific locations in the
  ' code for jumps (like for loops, IF/THEN blocks, etc.). They are resolved
  ' into memory addresses during the final linking/patching phase.

  ' Examples from the code: The tiraLabelNew$ function generates labels like
  ' &loopLbl_0, and the compiler internally creates labels like
  ' &END_PROGRAM.

  ' ~ (Tilde): Yes, this is for Ephemeral, localized TIRA scratchpad variables.
  ' "TIRA" stands for Three-Address Code, which is our intermediate
  ' representation. When a complex expression like A = (B + C) * D is being
  ' compiled, the intermediate result of (B + C) needs to be stored somewhere
  ' temporarily. The tiraDimVar$ function creates a unique temporary variable
  ' like ~T_0 for this purpose. These variables only exist for a moment within
  ' the context of a single statement's compilation.

  ' % (Percent Sign): Intended as a prefix for user-defined labels in the code in the editor
  ' Example 10: Print "Hello 20: Goto 10 - Internally, the system would use % for 10 and 20

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "GOTO NEEDS LABEL", ASIS, 0
    parse_GOTO = 0
    EXIT FUNCTION
  END IF

  ff = verifyNoExtraTokens(endIdx, startIdx + 1, "GOTO")
  IF ff = 0 THEN parse_GOTO = 0: EXIT FUNCTION

  targetTok$ = lineTokens$(startIdx + 1)
  targetLabelName$ = "%" + UCASE$(targetTok$)

  expectedSymType = TYPE_LABEL
  vIdx = resolveSymbol(targetLabelName$)
  IF vIdx = -1 THEN
    parse_GOTO = 0
    EXIT FUNCTION
  END IF

  genTempHeapReset

  ' Record location for Pass 4 patching using standard relative JMP
  ' MUST use JCC_MODE_FORWARD so opJcc returns the patch offset rather than 0!
  addPatch PATCH_GOTO, opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx, 0
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_GOTO = 0: EXIT FUNCTION

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_GOTO = tempSuccess

END FUNCTION ' parse_GOTO

''''''''''''''''''''''''
FUNCTION parse_IF (startIdx)

  tempSuccess = 0
  thenIdx = -1

  FOR ii = startIdx + 1 TO lineTokenCount - 1
    IF retTokenVal(lineTokens$(ii)) = TOK_THEN THEN
      thenIdx = ii
      EXIT FOR
    END IF
  NEXT

  IF thenIdx = -1 THEN
    throwCompilerError "MISSING THEN", ASIS, 0
    parse_IF = 0
    EXIT FUNCTION
  END IF

  truePatchCount = 0
  falsePatchCount = 0

  condRes = parseCondition(startIdx + 1, thenIdx - 1, 0, 1)
  IF condRes = 0 THEN
    parse_IF = 0
    EXIT FUNCTION
  END IF

  ' Unify multiple false patches into a single patch for the ELSE / END IF to resolve
  IF falsePatchCount > 1 THEN
    jmpTruePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    FOR ii = 0 TO falsePatchCount - 1
      patch32 falsePatches(ii), emitPos - (falsePatches(ii) + 4)
    NEXT

    unifiedFalsePatch = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

    patch8 jmpTruePos

    falsePatches(0) = unifiedFalsePatch
    falsePatchCount = 1
  END IF

  ' Any short-circuited TRUE jumps land here, right at the start of the THEN block
  FOR ii = 0 TO truePatchCount - 1
    patch32 truePatches(ii), emitPos - (truePatches(ii) + 4)
  NEXT

  IF thenIdx = lineTokenCount - 1 THEN
    ' Multi-line IF
    IF ctrlCount >= MAX_CTRLS THEN
      throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
      parse_IF = 0
      EXIT FUNCTION
    END IF
    ctrls(ctrlCount).Type = CTRL_IF
    ctrls(ctrlCount).Patch1 = falsePatches(0)
    ctrls(ctrlCount).Patch2 = 0 ' Initialize linked list for block end skips
    ctrlCount = ctrlCount + 1
    parse_IF = 1
  ELSE
    ' Single-line IF
    savedFalsePatch = falsePatches(0) ' Save locally before recursive parseStatement overwrites globals

    ' Scan for an ELSE token that belongs to THIS single-line IF
    elseIdx = -1
    parenDepth = 0
    ifDepth = 0
    FOR ii = thenIdx + 1 TO lineTokenCount - 1
      tVal = retTokenVal(lineTokens$(ii))
      IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
      IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1
      IF parenDepth = 0 THEN
        IF tVal = TOK_IF THEN ifDepth = ifDepth + 1
        IF tVal = TOK_ELSE THEN
          IF ifDepth = 0 THEN
            elseIdx = ii
            EXIT FOR
          ELSE
            ifDepth = ifDepth - 1
          END IF
        END IF
      END IF
    NEXT

    IF elseIdx = -1 THEN
      ' Standard single-line IF without ELSE
      stmtRes = parseStatement(thenIdx + 1)
      IF stmtRes = 0 THEN
        parse_IF = 0
        EXIT FUNCTION
      END IF

      patch32 savedFalsePatch, emitPos - (savedFalsePatch + 4)
      parse_IF = 1
    ELSE
      ' Single-line IF with an ELSE
      ' We dynamically restrict the parsing token window to hide the ELSE block from the THEN block
      savedlineTokenCount = lineTokenCount
      lineTokenCount = elseIdx

      stmtRes = parseStatement(thenIdx + 1)
      IF stmtRes = 0 THEN
        lineTokenCount = savedlineTokenCount ' Restore just in case
        parse_IF = 0
        EXIT FUNCTION
      END IF

      ' Restore the parsing window
      lineTokenCount = savedlineTokenCount

      ' Emit jump to skip the ELSE block since the TRUE block just finished
      jmpEnd = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' Resolve the false patch to land exactly here (at the start of the ELSE block)
      patch32 savedFalsePatch, emitPos - (savedFalsePatch + 4)

      ' Parse the ELSE block
      stmtRes = parseStatement(elseIdx + 1)
      IF stmtRes = 0 THEN
        parse_IF = 0
        EXIT FUNCTION
      END IF

      ' Resolve the TRUE block's skip jump to land here
      patch32 jmpEnd, emitPos - (jmpEnd + 4)

      parse_IF = 1
    END IF
  END IF

END FUNCTION ' parse_IF

''''''''''''''''''''''''
FUNCTION parse_INPUT (startIdx)

  tempSuccess = 0
  tokIdx = startIdx + 1

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF tokIdx > endIdx THEN
    throwCompilerError "EXPECTED VARIABLE", ASIS, 0
    parse_INPUT = 0
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
      parse_INPUT = 0
      EXIT FUNCTION
    END IF
    tVal = retTokenVal(lineTokens$(tokIdx))
    IF tVal = 256 + ASC(";") OR tVal = 256 + ASC(",") THEN
      tokIdx = tokIdx + 1
    ELSE
      throwCompilerError "EXPECTED ; OR ,", ASIS, 0
      parse_INPUT = 0
      EXIT FUNCTION
    END IF
  END IF

  IF tokIdx > endIdx THEN
    throwCompilerError "EXPECTED VARIABLE", ASIS, 0
    parse_INPUT = 0
    EXIT FUNCTION
  END IF

  vTok$ = lineTokens$(tokIdx)
  IF retTokenVal(vTok$) <> 0 THEN
    throwCompilerError "EXPECTED VARIABLE", ASIS, 0
    parse_INPUT = 0
    EXIT FUNCTION
  END IF

  vName$ = UCASE$(vTok$)

  vIdx = resolveSymbol(vName$)
  IF vIdx = -1 THEN
    parse_INPUT = 0
    EXIT FUNCTION
  END IF

  isStrVar = 0
  IF symbols(vIdx).DataType = TYPE_STRING THEN
    isStrVar = 1
  END IF

  IF hasPrompt = 1 THEN
    pStr$ = promptStr$
  ELSE
    pStr$ = "? "
  END IF

  IF compileHasGraphics = 0 THEN
    litIdx = resolveSymbol("!LIT" + cTrNum$(tempVarCounter) + "$")
    tempVarCounter = tempVarCounter + 1
    IF litIdx = -1 THEN parse_INPUT = 0: EXIT FUNCTION
    strVarData$(litIdx) = pStr$

    ' Descriptors handle length
    emitPrintString litIdx, 1
  END IF

  emitInput vIdx, isStrVar, pStr$

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_INPUT = tempSuccess

END FUNCTION ' parse_INPUT

''''''''''''''''''''''''
FUNCTION parse_LINE (startIdx)

  DIM boxType AS LONG

  tempSuccess = 0
  tokIdx = startIdx + 1

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF tokIdx > endIdx THEN
    throwCompilerError "LINE EXPECTS (", ASIS, 0
    parse_LINE = 0
    EXIT FUNCTION
  END IF

  dashIdx = -1
  pDepth = 0
  FOR ii = tokIdx TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
    IF pDepth = 0 THEN
      IF tVal = 256 + ASC("-") THEN
        dashIdx = ii
        EXIT FOR
      END IF
    END IF
  NEXT

  IF dashIdx = -1 THEN
    throwCompilerError "LINE MISSING -", ASIS, 0
    parse_LINE = 0
    EXIT FUNCTION
  END IF

  tiraStart

  '''' Parse X1, Y1
  retCoordinateBoundaries tokIdx, dashIdx - 1, cStart, cComma, cEnd
  IF cComma = -1 THEN
    throwCompilerError "LINE MISSING X1, Y1", ASIS, 0
    parse_LINE = 0
    EXIT FUNCTION
  END IF

  x1$ = tiraParseExpression$(cStart, cComma - 1, ALIM)
  IF x1$ = "" THEN parse_LINE = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COORDINATE MUST BE NUMERIC", ASIS, 0
    parse_LINE = 0: EXIT FUNCTION
  END IF
  x1$ = tiraForceInt$(x1$)

  y1$ = tiraParseExpression$(cComma + 1, cEnd, ALIM)
  IF y1$ = "" THEN parse_LINE = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COORDINATE MUST BE NUMERIC", ASIS, 0
    parse_LINE = 0: EXIT FUNCTION
  END IF
  y1$ = tiraForceInt$(y1$)

  '''' Parse X2, Y2, Color, Box
  comma3 = -1
  comma4 = -1
  pDepth = 0
  FOR ii = dashIdx + 1 TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
    IF pDepth = 0 THEN
      IF tVal = 256 + ASC(",") THEN
        IF comma3 = -1 THEN
          comma3 = ii
        ELSE
          IF comma4 = -1 THEN
            comma4 = ii
          END IF
        END IF
      END IF
    END IF
  NEXT

  p2End = endIdx
  IF comma3 <> -1 THEN p2End = comma3 - 1

  retCoordinateBoundaries dashIdx + 1, p2End, cStart, cComma, cEnd
  IF cComma = -1 THEN
    throwCompilerError "LINE MISSING X2, Y2", ASIS, 0
    parse_LINE = 0
    EXIT FUNCTION
  END IF

  x2$ = tiraParseExpression$(cStart, cComma - 1, ALIM)
  IF x2$ = "" THEN parse_LINE = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COORDINATE MUST BE NUMERIC", ASIS, 0
    parse_LINE = 0: EXIT FUNCTION
  END IF
  x2$ = tiraForceInt$(x2$)

  y2$ = tiraParseExpression$(cComma + 1, cEnd, ALIM)
  IF y2$ = "" THEN parse_LINE = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COORDINATE MUST BE NUMERIC", ASIS, 0
    parse_LINE = 0: EXIT FUNCTION
  END IF
  y2$ = tiraForceInt$(y2$)

  '''' Parse color
  IF comma3 <> -1 THEN
    colEnd = endIdx
    IF comma4 <> -1 THEN colEnd = comma4 - 1
    IF comma3 + 1 > colEnd THEN
      color$ = "!GFX_FG_RGB"
    ELSE
      color$ = tiraParseExpression$(comma3 + 1, colEnd, ALIM)
      IF color$ = "" THEN parse_LINE = 0: EXIT FUNCTION
      IF exprIs.DataType = TYPE_STRING THEN
        throwCompilerError "COLOR MUST BE NUMERIC", ASIS, 0
        parse_LINE = 0: EXIT FUNCTION
      END IF
      color$ = tiraForceInt$(color$)
    END IF
  ELSE
    color$ = "!GFX_FG_RGB"
  END IF

  '''' Parse box flag
  boxType = 0
  IF comma4 <> -1 THEN
    boxStr$ = UCASE$(lineTokens$(comma4 + 1))
    IF boxStr$ = "B" THEN boxType = 1
    IF boxStr$ = "BF" THEN boxType = 2
  END IF

  ' Compile arguments and invoke the runtime routine natively via TIRA
  tiraCall "RT_LINE", 7, x1$ + ", " + y1$ + ", " + x2$ + ", " + y2$ + ", " + color$ + ", " + LTRIM$(RTRIM$(STR$(boxType))) + ", 65535"

  tiraOp TC_REDRAW, "", "", ""

  tiraEndAndProcess

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_LINE = tempSuccess

END FUNCTION ' parse_LINE

''''''''''''''''''''''''
FUNCTION parse_LOCATE (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  commaIdx = -1
  parenDepth = 0
  FOR ii = startIdx + 1 TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
    IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1
    IF parenDepth = 0 AND tVal = 256 + ASC(",") THEN
      commaIdx = ii
      EXIT FOR
    END IF
  NEXT

  tiraStart

  IF commaIdx = -1 THEN
    yStr$ = tiraParseExpression$(startIdx + 1, endIdx, ALIM)
    IF yStr$ = "" THEN parse_LOCATE = 0: EXIT FUNCTION
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "LOCATE REQUIRES NUMERIC", ASIS, 0
      parse_LOCATE = 0
      EXIT FUNCTION
    END IF
    yStr$ = tiraForceInt$(yStr$)

    xStr$ = tiraDimVar$("T", TYPE_LONG)
    tiraAssign xStr$, "1"
  ELSE
    yStr$ = tiraParseExpression$(startIdx + 1, commaIdx - 1, ALIM)
    IF yStr$ = "" THEN parse_LOCATE = 0: EXIT FUNCTION
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "LOCATE REQUIRES NUMERIC", ASIS, 0
      parse_LOCATE = 0
      EXIT FUNCTION
    END IF
    yStr$ = tiraForceInt$(yStr$)

    xStr$ = tiraParseExpression$(commaIdx + 1, endIdx, ALIM)
    IF xStr$ = "" THEN parse_LOCATE = 0: EXIT FUNCTION
    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "LOCATE REQUIRES NUMERIC", ASIS, 0
      parse_LOCATE = 0
      EXIT FUNCTION
    END IF
    xStr$ = tiraForceInt$(xStr$)
  END IF

  tiraOp TC_SUB, yStr$, yStr$, "1"
  tiraOp TC_SUB, xStr$, xStr$, "1"

  IF compileHasGraphics = 1 THEN
    tiraOp TC_SHL, "!GFX_CUR_Y", yStr$, "3"
    tiraOp TC_SHL, "!GFX_CUR_X", xStr$, "3"
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

  tiraEndAndProcess

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_LOCATE = tempSuccess

END FUNCTION ' parse_LOCATE

''''''''''''''''''''''''
FUNCTION parse_LOOP (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "LOOP WITHOUT DO", ASIS, 0
    parse_LOOP = 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_DO THEN
    throwCompilerError "LOOP MISMATCH", ASIS, 0
    parse_LOOP = 0
    EXIT FUNCTION
  END IF

  ctrlCount = ctrlCount - 1
  loopTop = ctrls(ctrlCount).Patch1
  jmpExitPos = ctrls(ctrlCount).Patch2

  hasCond = 0

  IF endIdx > startIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx + 1))
    IF tVal = TOK_UNTIL THEN
      hasCond = 1
    ELSE
      throwCompilerError "EXPECTED UNTIL", ASIS, 0
      parse_LOOP = 0
      EXIT FUNCTION
    END IF
  END IF

  IF hasCond = 1 THEN
    truePatchCount = 0
    falsePatchCount = 0

    condRes = parseCondition(startIdx + 2, endIdx, 1, 0)
    IF condRes = 0 THEN
      parse_LOOP = 0
      EXIT FUNCTION
    END IF

    FOR ii = 0 TO falsePatchCount - 1
      patch32 falsePatches(ii), emitPos - (falsePatches(ii) + 4)
    NEXT

    genTempHeapReset

    ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, loopTop, JCC_TYPE_NEAR)

    FOR ii = 0 TO truePatchCount - 1
      patch32 truePatches(ii), emitPos - (truePatches(ii) + 4)
    NEXT
  ELSE
    genTempHeapReset

    ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, loopTop, JCC_TYPE_NEAR)
  END IF

  ' Walk the Patch2 linked list and resolve all successful block exit jumps to land here
  currentPatch = jmpExitPos
  DO WHILE currentPatch <> 0
    b1 = intermediateCode(currentPatch)
    b2 = intermediateCode(currentPatch + 1)
    b3 = intermediateCode(currentPatch + 2)
    b4 = intermediateCode(currentPatch + 3)

    prevPatch = b1
    prevPatch = prevPatch + (b2 * 256)
    prevPatch = prevPatch + (b3 * 65536)
    IF b4 > 0 THEN prevPatch = prevPatch + (b4 * 16777216)

    patch32 currentPatch, emitPos - (currentPatch + 4)
    currentPatch = prevPatch
  LOOP

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_LOOP = tempSuccess

END FUNCTION ' parse_LOOP

''''''''''''''''''''''''
FUNCTION parse_NEXT (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF ctrlCount = 0 THEN
    throwCompilerError "NEXT WITHOUT FOR", ASIS, 0
    parse_NEXT = 0
    EXIT FUNCTION
  END IF

  IF ctrls(ctrlCount - 1).Type <> CTRL_FOR THEN
    throwCompilerError "NEXT MISMATCH", ASIS, 0
    parse_NEXT = 0
    EXIT FUNCTION
  END IF

  ctrlCount = ctrlCount - 1
  vIdx = ctrls(ctrlCount).ForVarIdx
  endVarIdx = ctrls(ctrlCount).ForEndVarIdx
  stepVarIdx = ctrls(ctrlCount).ForStepVarIdx

  IF endIdx > startIdx THEN
    vTok$ = lineTokens$(startIdx + 1)
    baseName$ = UCASE$(vTok$)
    IF baseName$ <> RTRIM$(symbols(vIdx).RecordName) THEN
      throwCompilerError "NEXT VAR MISMATCH", ASIS, 0
      parse_NEXT = 0
      EXIT FUNCTION
    END IF
  END IF

  tiraStart

  vNameTira$ = RTRIM$(symbols(vIdx).RecordName)
  endNameTira$ = RTRIM$(symbols(endVarIdx).RecordName)
  stepNameTira$ = RTRIM$(symbols(stepVarIdx).RecordName)

  lblTop$ = "&FOR_TOP_" + cTrNum$(ctrlCount)
  lblCond$ = "&FOR_COND_" + cTrNum$(ctrlCount)
  lblPosStep$ = "&FOR_POS_" + cTrNum$(ctrlCount)
  lblNegStep$ = "&FOR_NEG_" + cTrNum$(ctrlCount)
  lblEndNext$ = "&FOR_DONE_" + cTrNum$(ctrlCount)

  ' Apply step logic
  tiraOp TC_ADD, vNameTira$, vNameTira$, stepNameTira$
  tiraLabel lblCond$

  ' Test step direction
  tiraJmpCond "JL", stepNameTira$, "0", lblNegStep$

  ' Positive Step Check (Jump to end if we exceeded the boundary)
  tiraLabel lblPosStep$
  tiraJmpCond "JG", vNameTira$, endNameTira$, lblEndNext$
  tiraAssign "!TEMP_HEAP_PTR", "!TEMP_HEAP_START"
  tiraJmp lblTop$

  ' Negative Step Check (Jump to end if we exceeded the boundary)
  tiraLabel lblNegStep$
  tiraJmpCond "JL", vNameTira$, endNameTira$, lblEndNext$
  tiraAssign "!TEMP_HEAP_PTR", "!TEMP_HEAP_START"
  tiraJmp lblTop$

  ' Loop conclusion
  tiraLabel lblEndNext$

  tiraEndAndProcess

  ' Resolve EXIT FOR linked list patching using manual pointer math post-TIRA
  currentPatch = ctrls(ctrlCount).Patch3
  DO WHILE currentPatch <> 0
    b1 = intermediateCode(currentPatch)
    b2 = intermediateCode(currentPatch + 1)
    b3 = intermediateCode(currentPatch + 2)
    b4 = intermediateCode(currentPatch + 3)

    prevPatch = b1
    prevPatch = prevPatch + (b2 * 256)
    prevPatch = prevPatch + (b3 * 65536)
    IF b4 > 0 THEN prevPatch = prevPatch + (b4 * 16777216)

    patch32 currentPatch, emitPos - (currentPatch + 4)
    currentPatch = prevPatch
  LOOP

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_NEXT = tempSuccess

END FUNCTION ' parse_NEXT

''''''''''''''''''''''''
FUNCTION parse_PRINT (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  suppressNewline = 0
  IF endIdx >= startIdx + 1 THEN
    lastTok$ = lineTokens$(endIdx)
    IF retTokenVal(lastTok$) = 256 + ASC(";") THEN
      suppressNewline = 1
      endIdx = endIdx - 1
    END IF
    IF retTokenVal(lastTok$) = 256 + ASC(",") THEN
      suppressNewline = 1
      endIdx = endIdx - 1
    END IF
  END IF

  IF endIdx < startIdx + 1 THEN
    IF suppressNewline = 0 THEN
      IF compileHasGraphics = 0 THEN emitCRLF_Console ELSE emitCRLF_Graphics
    END IF
  ELSE
    itemStart = startIdx + 1
    DO WHILE itemStart <= endIdx
      itemEnd = endIdx
      parenDepth = 0
      FOR ii = itemStart TO endIdx
        tVal = retTokenVal(lineTokens$(ii))
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
        exprRes = parseExpression(itemStart, itemEnd, 1)
        IF exprRes = 0 THEN
          parse_PRINT = 0
          EXIT FUNCTION
        END IF

        IF exprIs.DataType = TYPE_STRING THEN
          ' String Descriptor pointer is natively in RAX (0)
          ff = opMov(OP_TYPE_REG, 12, OP_TYPE_REG, 0, 64)
          IF compileHasGraphics = 0 THEN
            ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, -11, 32)
            ff = opCall(IAT_GETSTDHANDLE, CALLMODE_IAT)
            ff = opMov(OP_TYPE_MEM_RSP, stack.slotHandleSave, OP_TYPE_REG, 0, 64)
            ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 0, 64)
            ff = genLoadStringDesc(12, 2, 8)
            ff = opLea(OP_TYPE_REG, 9, OP_TYPE_MEM_RSP, stack.slotNumptrSpill, 64)
            ff = opMov(OP_TYPE_MEM_RSP, stack.slotOverlapped, OP_TYPE_IMM, 0, 64)
            ff = opCall(IAT_WRITEFILE, CALLMODE_IAT)
          ELSE
            ff = genLoadStringDesc(12, 10, 9)
            emitGraphicsConsoleAppend
          END IF
        ELSE
          emitPrintNumber 1
        END IF
      END IF

      itemStart = itemEnd + 2
    LOOP

    IF suppressNewline = 0 THEN
      IF compileHasGraphics = 0 THEN emitCRLF_Console ELSE emitCRLF_Graphics
    END IF
  END IF

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_PRINT = tempSuccess

END FUNCTION ' parse_PRINT

''''''''''''''''''''''''
FUNCTION parse_PSET (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  paren1 = -1
  comma1 = -1
  paren2 = -1
  comma2 = -1

  FOR ii = startIdx + 1 TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") AND paren1 = -1 THEN paren1 = ii
    IF tVal = 256 + ASC(",") THEN
      IF comma1 = -1 THEN
        comma1 = ii
      ELSE
        IF comma2 = -1 THEN
          comma2 = ii
        END IF
      END IF
    END IF
    IF tVal = 256 + ASC(")") AND paren2 = -1 THEN paren2 = ii
  NEXT

  parsed = 0

  ' Check for QBASIC style: PSET (X, Y), Color
  IF paren1 = startIdx + 1 AND comma1 <> -1 AND paren2 <> -1 AND comma2 <> -1 THEN
    IF paren1 < comma1 AND comma1 < paren2 AND paren2 < comma2 THEN
      xStart = paren1 + 1: xEnd = comma1 - 1
      yStart = comma1 + 1: yEnd = paren2 - 1
      cStart = comma2 + 1: cEnd = endIdx
      parsed = 1
    END IF
  END IF

  ' Fallback to old style: PSET X, Y, Color
  IF parsed = 0 THEN
    IF comma1 = -1 OR comma2 = -1 THEN
      throwCompilerError "PSET NEEDS X, Y, COLOR", ASIS, 0
      parse_PSET = 0
      EXIT FUNCTION
    END IF
    xStart = startIdx + 1: xEnd = comma1 - 1
    yStart = comma1 + 1: yEnd = comma2 - 1
    cStart = comma2 + 1: cEnd = endIdx
  END IF

  tiraStart

  xVar$ = tiraParseExpression$(xStart, xEnd, ALIM)
  IF xVar$ = "" THEN parse_PSET = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COORDINATE MUST BE NUMERIC", ASIS, 0
    parse_PSET = 0: EXIT FUNCTION
  END IF
  xVar$ = tiraForceInt$(xVar$)

  yVar$ = tiraParseExpression$(yStart, yEnd, ALIM)
  IF yVar$ = "" THEN parse_PSET = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COORDINATE MUST BE NUMERIC", ASIS, 0
    parse_PSET = 0: EXIT FUNCTION
  END IF
  yVar$ = tiraForceInt$(yVar$)

  cVar$ = tiraParseExpression$(cStart, cEnd, ALIM)
  IF cVar$ = "" THEN parse_PSET = 0: EXIT FUNCTION
  IF exprIs.DataType = TYPE_STRING THEN
    throwCompilerError "COLOR MUST BE NUMERIC", ASIS, 0
    parse_PSET = 0: EXIT FUNCTION
  END IF
  cVar$ = tiraForceInt$(cVar$)

  skipLbl$ = tiraLabelNew$("SKIP_PSET")

  ' Bounds check X
  tiraJmpCond "JL", xVar$, "0", skipLbl$
  tiraJmpCond "JGE", xVar$, cTrNum$(gfxConfig.SizeX), skipLbl$

  ' Bounds check Y
  tiraJmpCond "JL", yVar$, "0", skipLbl$
  tiraJmpCond "JGE", yVar$, cTrNum$(gfxConfig.SizeY), skipLbl$

  ' Color masking to byte limit (255)
  cMask$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_AND, cMask$, cVar$, "255"

  ' Offset calculation: (Y * Width) + X
  offsetVar$ = tiraDimVar$("T", TYPE_LONG)
  tiraOp TC_MUL, offsetVar$, yVar$, cTrNum$(gfxConfig.SizeX)
  tiraOp TC_ADD, offsetVar$, offsetVar$, xVar$

  ' Grab Base Framebuffer Ptr
  fbBase$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraNew TC_FRAMEBUF_PTR, fbBase$

  ' Target Address
  targetAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
  tiraOp TC_ADD, targetAddr$, fbBase$, offsetVar$

  ' Write Pixel
  tiraWriteMem targetAddr$, cMask$, "1"

  ' Off-screen boundary jump lands here
  tiraLabel skipLbl$

  ' Instruct backend to refresh invalid rect region
  tiraOp TC_REDRAW, "", "", ""

  tiraEndAndProcess

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_PSET = tempSuccess

END FUNCTION ' parse_PSET

''''''''''''''''''''''''
FUNCTION parse_ON (startIdx)

  DIM pushedDummy AS LONG

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endStmtIdx >= startIdx + 3 THEN
    IF retTokenVal(lineTokens$(startIdx + 1)) = TOK_ERROR THEN
      IF retTokenVal(lineTokens$(startIdx + 2)) = TOK_GOTO THEN
        lblTok$ = lineTokens$(startIdx + 3)
        IF lblTok$ <> "0" THEN
          lblName$ = "%" + UCASE$(lblTok$)
          vIdx = resolveSymbol(lblName$)
          IF vIdx = -1 THEN
            parse_ON = 0
            EXIT FUNCTION
          END IF

          ' Load the execution address of the label into RAX
          addPatch PATCH_GOTO, opLeaRegMemRIP(0), vIdx, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_ON = 0: EXIT FUNCTION

          ' Store RAX into !ERR_HANDLER_PTR
          errPtrIdx = resolveSymbol("!ERR_HANDLER_PTR")
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, errPtrIdx)
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_ON = 0: EXIT FUNCTION
        ELSE
          ' ON ERROR GOTO 0 (Disable error handling)
          errPtrIdx = resolveSymbol("!ERR_HANDLER_PTR")

          pushedDummy = 0
          IF updateStackAlignment = 1 THEN opPushReg 13: pushedDummy = 1
          opPushReg 12
          ff = opMov(OP_TYPE_REG, 12, OP_TYPE_IMM, 0, MODE_IMM64)
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 12, 64, errPtrIdx)
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_ON = 0: EXIT FUNCTION
          opPopReg 12
          IF pushedDummy = 1 THEN opPopReg 13
        END IF

        IF nextStmtIdx <> -1 THEN
          tempSuccess = parseStatement(nextStmtIdx)
        ELSE
          tempSuccess = 1
        END IF
        parse_ON = tempSuccess
        EXIT FUNCTION
      END IF
    END IF
  END IF

  throwCompilerError "UNSUPPORTED OR MALFORMED ON STATEMENT", ASIS, 0
  parse_ON = 0

END FUNCTION ' parse_ON

''''''''''''''''''''''''
FUNCTION parse_RESUME (startIdx)

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  ' Grab the preserved crashing instruction pointer saved in our VEH Handler
  ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, resolveSymbol("!LAST_ERR_RIP"))
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_RESUME = 0: EXIT FUNCTION

  ' Safely hop backwards to the point of origin
  ' jmp rax
  emitByteCode &HFF: emitByteCode &HE0

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_RESUME = tempSuccess

END FUNCTION ' parse_RESUME

''''''''''''''''''''''''
FUNCTION parse_RETURN (startIdx)

  DIM vIdx AS LONG
  DIM subIdx AS LONG
  DIM targetType AS LONG

  tempSuccess = 0

  endStmtIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF insideSub = 0 THEN
    throwCompilerError "RETURN OUTSIDE SUB OR FUNCTION", ASIS, 0
    parse_RETURN = 0
    EXIT FUNCTION
  END IF

  tiraStart

  IF endStmtIdx >= startIdx + 1 THEN
    IF insideSub <> 2 THEN
      throwCompilerError "SUB CANNOT RETURN A VALUE", ASIS, 0
      parse_RETURN = 0
      EXIT FUNCTION
    END IF

    argVar$ = tiraParseExpression$(startIdx + 1, endStmtIdx, ALIM)
    IF argVar$ = "" THEN parse_RETURN = 0: EXIT FUNCTION

    vIdx = resolveSymbol(currentSubName$)
    targetType = symbols(vIdx).DataType

    IF targetType = TYPE_STRING THEN
      IF exprIs.DataType <> TYPE_STRING THEN
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        parse_RETURN = 0
        EXIT FUNCTION
      END IF
      tiraCall "RT_STR_ASSIGN", 2, "&" + currentSubName$ + ", " + argVar$
    ELSE
      IF exprIs.DataType = TYPE_STRING THEN
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        parse_RETURN = 0
        EXIT FUNCTION
      END IF
      tiraAssign currentSubName$, argVar$
    END IF
  END IF

  tiraEndAndProcess

  ' Route control flow to the true epilogue using a forward jump
  vIdx = resolveSymbol(currentSubName$)
  IF vIdx <> -1 THEN
    subIdx = symbols(vIdx).SubIndex
    IF subIdx <> -1 THEN
      genTempHeapReset

      jmpExit = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
      patch32 jmpExit, subs(subIdx).ExitPatchList
      subs(subIdx).ExitPatchList = jmpExit
    END IF
  END IF

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parse_RETURN = tempSuccess

END FUNCTION ' parse_RETURN

''''''''''''''''''''''''
FUNCTION parse_SELECT (startIdx)

  tempSuccess = 0

  endIdx = findInstructionEnd(startIdx + 1)
  nextStmtIdx = returnedData2

  IF endIdx < startIdx + 1 THEN
    throwCompilerError "MALFORMED SELECT CASE", ASIS, 0
    parse_SELECT = 0
    EXIT FUNCTION
  END IF

  IF retTokenVal(lineTokens$(startIdx + 1)) <> TOK_CASE THEN
    throwCompilerError "EXPECTED CASE AFTER SELECT", ASIS, 0
    parse_SELECT = 0
    EXIT FUNCTION
  END IF

  exprRes = parseExpression(startIdx + 2, endIdx, 1)
  IF exprRes = 0 THEN
    parse_SELECT = 0
    EXIT FUNCTION
  END IF

  IF exprIs.DataType = TYPE_STRING THEN
    hiddenName$ = "!SEL_SVAR_" + cTrNum$(ctrlCount) + "$"
  ELSE
    hiddenName$ = "!SEL_NVAR_" + cTrNum$(ctrlCount)
  END IF

  hiddenVarIdx = resolveSymbol(hiddenName$)
  IF hiddenVarIdx = -1 THEN
    parse_SELECT = 0
    EXIT FUNCTION
  END IF

  ' Ensure string descriptors are cloned correctly using the runtime helper to prevent data loss
  IF exprIs.DataType = TYPE_STRING THEN
    ' Value is natively in RAX (0) from parseExpression
    ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)

    ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, hiddenVarIdx)
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_SELECT = 0: EXIT FUNCTION

    addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_SELECT = 0: EXIT FUNCTION
  ELSE
    ' Extract directly from hardware registers
    IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
      IF exprIs.DataType = TYPE_SINGLE THEN
        ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
      END IF
      ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, hiddenVarIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_SELECT = 0: EXIT FUNCTION
    ELSE
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, hiddenVarIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parse_SELECT = 0: EXIT FUNCTION
    END IF
  END IF

  IF ctrlCount >= MAX_CTRLS THEN
    throwCompilerError "CONTROL STACK OVERFLOW", ASIS, 0
    parse_SELECT = 0
    EXIT FUNCTION
  END IF

  ctrls(ctrlCount).Type = CTRL_SELECT
  ctrls(ctrlCount).SelectVarIdx = hiddenVarIdx
  ctrls(ctrlCount).Patch1 = 0
  ctrls(ctrlCount).Patch2 = 0 ' Represents the head of the END SELECT jump chain
  ctrls(ctrlCount).SelectCaseSeen = 0 ' 0 means no CASE seen yet

  IF exprIs.DataType = TYPE_STRING THEN
    ctrls(ctrlCount).SelectDataType = TYPE_STRING
  ELSE
    IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
      ctrls(ctrlCount).SelectDataType = TYPE_DOUBLE
    ELSE
      ctrls(ctrlCount).SelectDataType = TYPE_LONG
    END IF
  END IF

  ctrlCount = ctrlCount + 1

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF
  parse_SELECT = tempSuccess

END FUNCTION ' parse_SELECT

''''''''''''''''''''''''
FUNCTION parseAssign (startIdx)

  DIM opMode AS LONG
  DIM isSingle AS LONG
  DIM destLen AS LONG
  DIM jmpSkipMin AS LONG
  DIM jmpSkipPad AS LONG
  DIM jmpHasDesc AS LONG
  DIM exprRes AS LONG
  DIM targetType AS LONG
  DIM isStrVar AS LONG
  DIM isFixedStr AS LONG
  DIM udtOffset AS LONG
  DIM lenIdx AS LONG
  DIM fFound AS LONG
  DIM uIdx AS LONG
  DIM tempUdtIndex AS LONG
  DIM rhsTokIdx AS LONG
  DIM rhsName$
  DIM rhsIdx AS LONG
  DIM rhsHasIndex AS LONG
  DIM rhsParenStart AS LONG
  DIM rhsCloseParenIdx AS LONG
  DIM rhsCommaIdx AS LONG
  DIM rhsAxIdx AS LONG
  DIM rhsHasField AS LONG
  DIM rhsUdtOffset AS LONG
  DIM rhsUdtIndex AS LONG
  DIM rhsFieldName$
  DIM rUIdx AS LONG
  DIM rFFound AS LONG
  DIM lhsUdtIndex AS LONG
  DIM fieldCnt AS LONG
  DIM fieldOffset AS LONG
  DIM fieldSize AS LONG
  DIM fType AS LONG
  DIM f AS LONG
  DIM axIdx AS LONG
  DIM elemSize AS LONG
  DIM jmpSkipNull AS LONG
  DIM emptyDescIdx AS LONG
  DIM jmpSkipRhsNull AS LONG

  tempSuccess = 0
  vTok$ = lineTokens$(startIdx)
  vTokVal = retTokenVal(vTok$)

  IF vTokVal = 0 AND LEN(vTok$) > 0 THEN
    vName$ = UCASE$(vTok$)

    endStmtIdx = findInstructionEnd(startIdx + 1)
    nextStmtIdx = returnedData2

    tokIdx = startIdx + 1
    hasIndex = 0
    hasField = 0
    udtOffset = 0
    closeParenIdx = -1
    commaIdx = -1

    ' 1. Check Array Index
    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
        hasIndex = 1
        closeParenIdx = findMatchingParen(tokIdx, endStmtIdx)

        IF closeParenIdx = -1 THEN
          throwCompilerError "MISSING )", ASIS, 0
          parseAssign = 0: EXIT FUNCTION
        END IF

        ' Check for comma (2D array)
        commaIdx = findNextTokenAtDepth0(tokIdx + 1, closeParenIdx - 1, 256 + ASC(","))

        tokIdx = closeParenIdx + 1
      END IF
    END IF

    ' 2. Check UDT Field
    IF tokIdx <= endStmtIdx THEN
      IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(".") THEN
        hasField = 1
        ' We must skip the field name to find '='
        tokIdx = tokIdx + 2
      END IF
    END IF

    ' 3. Verify "="
    IF tokIdx > endStmtIdx OR retTokenVal(lineTokens$(tokIdx)) <> 256 + ASC("=") THEN
      throwCompilerError "EXPECTED =", ASIS, 0
      parseAssign = 0: EXIT FUNCTION
    END IF
    eqIdx = tokIdx

    vIdx = resolveSymbol(vName$)
    IF vIdx = -1 THEN parseAssign = 0: EXIT FUNCTION
    targetType = symbols(vIdx).DataType

    isStrVar = 0
    isFixedStr = 0

    ' Process the UDT field properly since vIdx is resolved
    IF hasField = 1 THEN
      fNameTok$ = UCASE$(lineTokens$(eqIdx - 1))

      IF symbols(vIdx).DataType <> TYPE_UDT THEN
        throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF

      uIdx = symbols(vIdx).UDTIndex
      fFound = 0
      FOR f = 0 TO udts(uIdx).FieldCount - 1
        IF RTRIM$(udtFields(uIdx, f).FieldName) = fNameTok$ THEN
          udtOffset = udtFields(uIdx, f).Offset
          targetType = udtFields(uIdx, f).DataType
          destLen = udtFields(uIdx, f).Size
          tempUdtIndex = udtFields(uIdx, f).UDTIndex
          fFound = 1
          EXIT FOR
        END IF
      NEXT

      IF fFound = 0 THEN
        throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF
    END IF

    IF targetType = TYPE_STRING THEN
      isStrVar = 1
      IF hasField = 1 THEN
        IF tempUdtIndex = 0 THEN
          isFixedStr = 1
        ELSE
          isFixedStr = 0
        END IF
      ELSE
        lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
        IF floatVarData(lenIdx) > 0 THEN isFixedStr = 1
      END IF
    END IF

    IF hasIndex = 1 THEN
      IF symbols(vIdx).IsArray = 0 THEN
        throwCompilerError "ARRAY NOT DIMMED", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF

      IF commaIdx <> -1 AND symbols(vIdx).Size2 = 0 AND symbols(vIdx).IsArray <> 2 THEN
        throwCompilerError "EXPECTED 2D ARRAY", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF
      IF commaIdx = -1 AND symbols(vIdx).Size2 > 0 AND symbols(vIdx).IsArray <> 2 THEN
        throwCompilerError "EXPECTED 2D ARRAY", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF
    END IF

    ' 4. Array Index Pre-Evaluation
    IF hasIndex = 1 THEN
      IF commaIdx = -1 THEN
        ff = genForceNumericIntEx(startIdx + 2, closeParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
        IF ff = 0 THEN parseAssign = 0: EXIT FUNCTION
        opPushReg 0 ' Push X
      ELSE
        ff = genForceNumericIntEx(startIdx + 2, commaIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
        IF ff = 0 THEN parseAssign = 0: EXIT FUNCTION
        opPushReg 0 ' Push X

        ff = genForceNumericIntEx(commaIdx + 1, closeParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
        IF ff = 0 THEN parseAssign = 0: EXIT FUNCTION
        opPushReg 0 ' Push Y
      END IF
    END IF

    ' UDT Deep Copy Block
    IF targetType = TYPE_UDT THEN
      rhsTokIdx = eqIdx + 1
      IF rhsTokIdx > endStmtIdx THEN
        throwCompilerError "EXPECTED UDT VARIABLE", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF

      rhsName$ = UCASE$(lineTokens$(rhsTokIdx))
      rhsIdx = resolveSymbol(rhsName$)
      IF rhsIdx = -1 THEN parseAssign = 0: EXIT FUNCTION

      rhsTokIdx = rhsTokIdx + 1

      rhsHasIndex = 0
      rhsParenStart = 0
      rhsCloseParenIdx = -1
      rhsCommaIdx = -1

      IF rhsTokIdx <= endStmtIdx THEN
        IF retTokenVal(lineTokens$(rhsTokIdx)) = 256 + ASC("(") THEN
          rhsHasIndex = 1
          rhsParenStart = rhsTokIdx
          rhsCloseParenIdx = findMatchingParen(rhsTokIdx, endStmtIdx)
          IF rhsCloseParenIdx = -1 THEN
            throwCompilerError "MISSING )", ASIS, 0
            parseAssign = 0: EXIT FUNCTION
          END IF
          rhsCommaIdx = findNextTokenAtDepth0(rhsTokIdx + 1, rhsCloseParenIdx - 1, 256 + ASC(","))
          rhsTokIdx = rhsCloseParenIdx + 1
        END IF
      END IF

      rhsHasField = 0
      rhsUdtOffset = 0
      rhsUdtIndex = -1

      IF symbols(rhsIdx).DataType = TYPE_UDT THEN
        rhsUdtIndex = symbols(rhsIdx).UDTIndex
      END IF

      IF rhsTokIdx <= endStmtIdx THEN
        IF retTokenVal(lineTokens$(rhsTokIdx)) = 256 + ASC(".") THEN
          rhsHasField = 1
          rhsTokIdx = rhsTokIdx + 1
          IF rhsTokIdx > endStmtIdx THEN
            throwCompilerError "EXPECTED FIELD NAME", ASIS, 0
            parseAssign = 0: EXIT FUNCTION
          END IF

          rhsFieldName$ = UCASE$(lineTokens$(rhsTokIdx))
          rhsTokIdx = rhsTokIdx + 1

          IF symbols(rhsIdx).DataType <> TYPE_UDT THEN
            throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
            parseAssign = 0: EXIT FUNCTION
          END IF

          rUIdx = symbols(rhsIdx).UDTIndex
          rFFound = 0
          FOR f = 0 TO udts(rUIdx).FieldCount - 1
            IF RTRIM$(udtFields(rUIdx, f).FieldName) = rhsFieldName$ THEN
              rhsUdtOffset = udtFields(rUIdx, f).Offset
              IF udtFields(rUIdx, f).DataType <> TYPE_UDT THEN
                throwCompilerError "TYPE MISMATCH", ASIS, 0
                parseAssign = 0: EXIT FUNCTION
              END IF
              rhsUdtIndex = udtFields(rUIdx, f).UDTIndex
              rFFound = 1
              EXIT FOR
            END IF
          NEXT

          IF rFFound = 0 THEN
            throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
            parseAssign = 0: EXIT FUNCTION
          END IF
        END IF
      END IF

      IF rhsUdtIndex = -1 THEN
        throwCompilerError "RHS IS NOT A UDT", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF

      lhsUdtIndex = symbols(vIdx).UDTIndex
      IF hasField = 1 THEN lhsUdtIndex = tempUdtIndex

      IF rhsUdtIndex <> lhsUdtIndex THEN
        throwCompilerError "UDT TYPE MISMATCH", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF

      IF rhsHasIndex = 1 THEN
        IF symbols(rhsIdx).IsArray = 0 THEN
          throwCompilerError "ARRAY NOT DIMMED", ASIS, 0
          parseAssign = 0: EXIT FUNCTION
        END IF

        IF rhsCommaIdx = -1 THEN
          ff = genForceNumericIntEx(rhsParenStart + 1, rhsCloseParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
          IF ff = 0 THEN parseAssign = 0: EXIT FUNCTION
          opPushReg 0 ' Push X
        ELSE
          ff = genForceNumericIntEx(rhsParenStart + 1, rhsCommaIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
          IF ff = 0 THEN parseAssign = 0: EXIT FUNCTION
          opPushReg 0 ' Push X

          ff = genForceNumericIntEx(rhsCommaIdx + 1, rhsCloseParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
          IF ff = 0 THEN parseAssign = 0: EXIT FUNCTION
          opPushReg 0 ' Push Y
        END IF
      END IF

      ' Calculate RHS Address into R9
      IF symbols(rhsIdx).IsArray = 2 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 9, OP_TYPE_MEM_RIP, 0, 64, rhsIdx)
      ELSE
        ff = genSymbolRouteLea(9, rhsIdx)
      END IF

      IF rhsHasIndex = 1 THEN
        IF rhsCommaIdx <> -1 THEN
          opPopReg 3 ' Y
          opPopReg 0 ' X
          rhsAxIdx = resolveSymbol("!" + RTRIM$(symbols(rhsIdx).RecordName) + "_AX")
          ff = genSymbolRouteMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64, rhsAxIdx)
          ff = opImul(3, OP_TYPE_REG, 8, 0, MODE_IMUL64_REG)
          ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
        ELSE
          opPopReg 0 ' X
        END IF

        elemSize = udts(symbols(rhsIdx).UDTIndex).TotalSize
        IF elemSize <> 1 THEN
          ff = opImul(0, OP_TYPE_REG, 0, elemSize, MODE_IMUL64_IMM32)
        END IF

        ff = opALU(ALU_ADD, OP_TYPE_REG, 9, OP_TYPE_REG, 0, 64)
      END IF

      IF rhsUdtOffset > 0 THEN
        ff = opALU(ALU_ADD, OP_TYPE_REG, 9, OP_TYPE_IMM, rhsUdtOffset, 64)
      END IF

      opPushReg 9 ' Save RHS Address to stack securely

      ' Calculate LHS address into R8
      IF symbols(vIdx).IsArray = 2 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64, vIdx)
      ELSE
        ff = genSymbolRouteLea(8, vIdx)
      END IF

      IF hasIndex = 1 THEN
        IF commaIdx <> -1 THEN
          opPopReg 3 ' Y
          opPopReg 0 ' X
          axIdx = resolveSymbol("!" + RTRIM$(symbols(vIdx).RecordName) + "_AX")
          ff = genSymbolRouteMov(OP_TYPE_REG, 10, OP_TYPE_MEM_RIP, 0, 64, axIdx)
          ff = opImul(3, OP_TYPE_REG, 10, 0, MODE_IMUL64_REG)
          ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
        ELSE
          opPopReg 0 ' X
        END IF

        elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
        IF elemSize <> 1 THEN
          ff = opImul(0, OP_TYPE_REG, 0, elemSize, MODE_IMUL64_IMM32)
        END IF

        ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_REG, 0, 64)
      END IF

      IF udtOffset > 0 THEN
        ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_IMM, udtOffset, 64)
      END IF

      opPopReg 9 ' Restore RHS Address from stack into R9

      ' Process UDT fields for structural deep copy
      fieldCnt = udts(lhsUdtIndex).FieldCount

      FOR f = 0 TO fieldCnt - 1
        fieldOffset = udtFields(lhsUdtIndex, f).Offset
        fieldSize = udtFields(lhsUdtIndex, f).Size
        fType = udtFields(lhsUdtIndex, f).DataType

        IF fType = TYPE_STRING AND udtFields(lhsUdtIndex, f).UDTIndex = 1 THEN
          ' Get RHS Desc Ptr
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 9, 64)
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, fieldOffset, 64)
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG, 2, 64) ' RDX = [RHS + offset]

          ' If RDX is NULL, point it to !EMPTY_DESC$
          ff = opTest(OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)
          jmpSkipRhsNull = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
          emptyDescIdx = resolveSymbol("!EMPTY_DESC$")
          ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64, emptyDescIdx)
          patch8 jmpSkipRhsNull

          ' Get LHS Desc Ptr (and allocate if NULL)
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 1, OP_TYPE_IMM, fieldOffset, 64)

          ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG, 1, 64) ' R10 = actual pointer
          ff = opTest(OP_TYPE_REG, 10, OP_TYPE_REG, 10, 64)
          jmpHasDesc = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' Allocate 24 bytes
          opPushReg 1
          opPushReg 2
          opPushReg 8
          opPushReg 9

          ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32) ' HEAP_ZERO_MEMORY
          ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 24, 32)
          ff = genAlignedCall(IAT_HEAPALLOC, 13, DEFAULT)
          ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 0, 64) ' R10 = new alloc

          opPopReg 9
          opPopReg 8
          opPopReg 2
          opPopReg 1

          ' Store new desc pointer into LHS field
          ff = opMov(OP_TYPE_MEM_REG, 1, OP_TYPE_REG, 10, 64)

          patch8 jmpHasDesc

          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 10, 64) ' RCX = LHS Desc Ptr

          opPushReg 8
          opPushReg 9
          addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseAssign = 0: EXIT FUNCTION
          opPopReg 9
          opPopReg 8
        ELSE
          ' Raw block transfer (Fixed strings, numbers, embedded static sub-structs)
          ff = opMov(OP_TYPE_REG, 7, OP_TYPE_REG, 8, 64) ' RDI
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 7, OP_TYPE_IMM, fieldOffset, 64)

          ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 9, 64) ' RSI
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_IMM, fieldOffset, 64)

          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, fieldSize, 64) ' RCX

          opPushReg 8
          opPushReg 9

          opFlag FLAG_CLD
          opString STR_MOVS, REP_REP, 8

          opPopReg 9
          opPopReg 8
        END IF
      NEXT f

      IF nextStmtIdx <> -1 THEN
        tempSuccess = parseStatement(nextStmtIdx)
      ELSE
        tempSuccess = 1
      END IF

      parseAssign = tempSuccess
      EXIT FUNCTION

    ELSE

      ' 5. Evaluate RHS Expression (Scalar Types)
      exprRes = parseExpression(eqIdx + 1, endStmtIdx, 0)
      IF exprRes = 0 THEN parseAssign = 0: EXIT FUNCTION

      IF targetType = TYPE_STRING AND exprIs.DataType <> TYPE_STRING THEN
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF
      IF targetType <> TYPE_STRING AND targetType <> TYPE_UDT AND exprIs.DataType = TYPE_STRING THEN
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        parseAssign = 0: EXIT FUNCTION
      END IF

      ' Save RHS result to the hardware stack safely so address math can use GPRs
      IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
        ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      END IF
      opPushReg 0

      ' 6. Calculate Address (if Array or Field)
      IF hasIndex = 1 OR hasField = 1 THEN
        ' Pop RHS to R12 temporarily to clear the stack for index retrieval
        opPopReg 12

        ' Base address into RDX (2)
        IF symbols(vIdx).IsArray = 2 THEN
          ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64, vIdx)
        ELSE
          ff = genSymbolRouteLea(2, vIdx)
        END IF

        IF hasIndex = 1 THEN
          ' Restore X to RAX
          IF commaIdx <> -1 THEN
            ' Restore Y to RBX
            opPopReg 3
            ' Restore X to RAX
            opPopReg 0

            ' Multiply Y by AX (Stride X)
            axIdx = resolveSymbol("!" + RTRIM$(symbols(vIdx).RecordName) + "_AX")
            ff = genSymbolRouteMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64, axIdx)
            ff = opImul(3, OP_TYPE_REG, 8, 0, MODE_IMUL64_REG)
            ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64) ' RAX = X + Y * AX
          ELSE
            ' Restore X to RAX
            opPopReg 0
          END IF

          ' Multiply RAX by elemSize
          elemSize = 8

          SELECT CASE symbols(vIdx).DataType

            CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
            CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
            CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
            CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
            CASE TYPE_STRING
              IF hasField = 0 THEN
                lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
                IF floatVarData(lenIdx) > 0 THEN
                  elemSize = floatVarData(lenIdx)
                ELSE
                  elemSize = 8
                END IF
              END IF

          END SELECT ' symbols(vIdx).DataType

          IF elemSize <> 1 THEN
            ff = opImul(0, OP_TYPE_REG, 0, elemSize, MODE_IMUL64_IMM32)
          END IF

          ' Add to Base (RDX)
          ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
        END IF

        IF udtOffset > 0 THEN
          ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, udtOffset, 64)
        END IF

        ' Restore RHS from R12 to RAX
        ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 12, 64)
      ELSE
        ' Restore RHS directly to RAX since no address math was needed
        opPopReg 0
      END IF

      ' 7. Restore RHS and Convert/Store
      IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
        isSingle = 0
        IF targetType = TYPE_SINGLE THEN isSingle = 1

        IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        ELSE
          ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          exprIs.DataType = TYPE_DOUBLE
        END IF

        IF exprIs.DataType = TYPE_DOUBLE AND isSingle = 1 THEN
          ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        END IF
        IF exprIs.DataType = TYPE_SINGLE AND isSingle = 0 THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
        END IF

        opMode = MODE_SSE_DOUBLE
        IF isSingle = 1 THEN opMode = MODE_SSE_SINGLE

        IF hasIndex = 1 OR hasField = 1 THEN
          ff = opSSE(SSE_MOV, OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, opMode)
        ELSE
          ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, opMode, vIdx)
        END IF
      ELSE
        IF targetType = TYPE_STRING THEN
          ' String Assignment Routing
          IF hasIndex = 0 AND hasField = 0 THEN
            ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64) ' RDX = RHS Desc
            ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, vIdx) ' RCX = LHS Desc

            IF isFixedStr = 1 THEN
              ' Inline fixed string copy with truncation and space padding
              opPushReg 6 ' rsi
              opPushReg 7 ' rdi

              ' Load Src DataAddress (R9) and Src Length (R8) from RHS Desc (RDX)
              ff = opMov(OP_TYPE_REG, 9, OP_TYPE_MEM_REG, 2, 64)
              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG_DISP8, 2 + (8 * 256), 64)

              ' Dest DataAddress = [RCX]
              ff = opMov(OP_TYPE_REG, 7, OP_TYPE_MEM_REG, 1, 64)
              ' Dest Length = [RCX+8]
              ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG_DISP8, 1 + (8 * 256), 64)

              ' R11 = Dest Length (saved for padding calculations safely away from rep count)
              ff = opMov(OP_TYPE_REG, 11, OP_TYPE_REG, 10, 64)

              ' min(Dest Len, Src Len)
              ff = opALU(ALU_CMP, OP_TYPE_REG, 10, OP_TYPE_REG, 8, 64)
              jmpSkipMin = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
              ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 8, 64)
              patch8 jmpSkipMin

              ' Copy min length bytes from R9 to R7
              ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 9, 64)
              opPushReg 1
              ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 10, 64)
              opFlag FLAG_CLD
              opString STR_MOVS, REP_REP, 8
              opPopReg 1

              ' Pad spaces (R11 - min_len)
              ff = opALU(ALU_SUB, OP_TYPE_REG, 11, OP_TYPE_REG, 10, 64)
              jmpSkipPad = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
              opPushReg 1
              ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 11, 64)
              ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, 32, 8)
              opString STR_STOS, REP_REP, 8
              opPopReg 1
              patch8 jmpSkipPad

              opPopReg 7
              opPopReg 6
            ELSE
              ' Call RT_STR_ASSIGN runtime helper
              addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseAssign = 0: EXIT FUNCTION
            END IF
          ELSE
            ' Address is in RDX (2)
            IF isFixedStr = 1 THEN
              opPushReg 6
              opPushReg 7
              ff = opMov(OP_TYPE_REG, 7, OP_TYPE_REG, 2, 64) ' Dest DataAddress = RDX
              IF hasField = 0 THEN destLen = floatVarData(lenIdx)
              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, destLen, 64)
              ff = opMov(OP_TYPE_REG, 6, OP_TYPE_MEM_REG, 0, 64) ' Src DataAddress
              ff = opMov(OP_TYPE_REG, 9, OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), 64) ' Src Len
              ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 8, 64)
              ff = opALU(ALU_CMP, OP_TYPE_REG, 10, OP_TYPE_REG, 9, 64)
              jmpSkipMin = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
              ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 9, 64)
              patch8 jmpSkipMin
              ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 10, 64)
              opFlag FLAG_CLD
              opString STR_MOVS, REP_REP, 8
              ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)
              ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_REG, 10, 64)
              jmpSkipPad = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
              ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, 32, 8)
              opString STR_STOS, REP_REP, 8
              patch8 jmpSkipPad
              opPopReg 7
              opPopReg 6
            ELSE
              ' Dynamic String Array Element OR Dynamic UDT Field
              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 2, 64)
              ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
              jmpHasDesc = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

              opPushReg 0
              opPushReg 2
              opPushReg 13
              ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
              ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32)
              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 24, 32)
              ff = genAlignedCall(IAT_HEAPALLOC, 13, DEFAULT)
              ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 0, 64)
              opPopReg 13
              opPopReg 2
              opPopReg 0
              ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 8, 64)

              patch8 jmpHasDesc
              ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64) ' LHS
              ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64) ' RHS
              addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
            END IF
          END IF
        ELSE
          ' Standard Scalar Integer Routing
          IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
          END IF

          IF hasIndex = 1 OR hasField = 1 THEN

            SELECT CASE targetType

              CASE TYPE_BYTE, TYPE_UBYTE
                ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 8)
              CASE TYPE_INTEGER, TYPE_UINTEGER
                ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 16)
              CASE TYPE_LONG, TYPE_ULONG
                ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 32)
              CASE ELSE
                ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 64)

            END SELECT ' targetType

          ELSE

            SELECT CASE targetType

              CASE TYPE_BYTE, TYPE_UBYTE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 8, vIdx)
              CASE TYPE_INTEGER, TYPE_UINTEGER
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 16, vIdx)
              CASE TYPE_LONG, TYPE_ULONG
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, vIdx)
              CASE ELSE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, vIdx)

            END SELECT ' targetType

          END IF
        END IF
      END IF

      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseAssign = 0: EXIT FUNCTION

      IF nextStmtIdx <> -1 THEN
        tempSuccess = parseStatement(nextStmtIdx)
      ELSE
        tempSuccess = 1
      END IF

      parseAssign = tempSuccess
      EXIT FUNCTION

    END IF
  END IF

  parseAssign = tempSuccess

END FUNCTION ' parseAssign

''''''''''''''''''''''''
FUNCTION parseCondition (startIdx, endIdx, jumpOnTrue AS LONG, jumpOnFalse AS LONG)

  ' Might have been called parseCompare, but also recursively handles AND and OR chains

  DIM condCode AS LONG
  DIM leftDataType AS LONG
  DIM rightDataType AS LONG
  DIM hasRelational AS LONG

  ' Check for parens wrapping the entire condition and strip them to resolve internals
  stripParens = 0
  IF retTokenVal(lineTokens$(startIdx)) = 256 + ASC("(") THEN
    IF findMatchingParen(startIdx, endIdx) = endIdx THEN
      stripParens = 1
    END IF
  END IF

  IF stripParens = 1 THEN
    tempRes = parseCondition(startIdx + 1, endIdx - 1, jumpOnTrue, jumpOnFalse)
    parseCondition = tempRes
    EXIT FUNCTION
  END IF

  ' Scan for any relational operators anywhere in the expression (at any depth)
  ' If there are no relational operators, this is a purely mathematical/bitwise
  ' expression (e.g., "Flags AND 8"). We bypass short-circuit splitting and let
  ' the AST handle it natively so bitwise masking remains perfectly intact.
  hasRelational = 0
  FOR ii = startIdx TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("=") OR tVal = 256 + ASC("<") OR tVal = 256 + ASC(">") THEN
      hasRelational = 1
      EXIT FOR
    END IF
  NEXT

  IF hasRelational = 1 THEN
    ' Find unparenthesized OR
    opIdx = findNextTokenAtDepth0(startIdx, endIdx, TOK_OR)

    IF opIdx <> -1 THEN
      ' OR found. Use short-circuit branching
      ' LHS must jump on true, but will fall through to RHS on false
      prevFalseCount = falsePatchCount

      lhsRes = parseCondition(startIdx, opIdx - 1, 1, 0)
      IF lhsRes = 0 THEN
        parseCondition = 0
        EXIT FUNCTION
      END IF

      ' False patches generated by LHS must land right here at the start of RHS
      FOR ii = prevFalseCount TO falsePatchCount - 1
        patch32 falsePatches(ii), emitPos - (falsePatches(ii) + 4)
      NEXT
      falsePatchCount = prevFalseCount

      ' RHS inherits parent conditions
      rhsRes = parseCondition(opIdx + 1, endIdx, jumpOnTrue, jumpOnFalse)
      IF rhsRes = 0 THEN
        parseCondition = 0
        EXIT FUNCTION
      END IF

      parseCondition = 1
      EXIT FUNCTION
    END IF

    ' Find unparenthesized AND
    opIdx = findNextTokenAtDepth0(startIdx, endIdx, TOK_AND)

    IF opIdx <> -1 THEN
      ' AND found. Use short-circuit branching
      ' LHS must jump on false, but will fall through to RHS on true
      prevTrueCount = truePatchCount

      lhsRes = parseCondition(startIdx, opIdx - 1, 0, 1)
      IF lhsRes = 0 THEN
        parseCondition = 0
        EXIT FUNCTION
      END IF

      ' True patches generated by LHS must land right here at the start of RHS
      FOR ii = prevTrueCount TO truePatchCount - 1
        patch32 truePatches(ii), emitPos - (truePatches(ii) + 4)
      NEXT
      truePatchCount = prevTrueCount

      ' RHS inherits parent conditions
      rhsRes = parseCondition(opIdx + 1, endIdx, jumpOnTrue, jumpOnFalse)
      IF rhsRes = 0 THEN
        parseCondition = 0
        EXIT FUNCTION
      END IF

      parseCondition = 1
      EXIT FUNCTION
    END IF
  END IF

  ' Base Case: No OR/AND found, perform standard relational scan
  opIdx = -1
  opLen = 1
  opType = 0 ' 1: =, 2: <, 3: >, 4: <=, 5: >=, 6: <>

  parenDepth = 0
  FOR ii = startIdx TO endIdx
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN parenDepth = parenDepth + 1
    IF tVal = 256 + ASC(")") THEN parenDepth = parenDepth - 1
    IF parenDepth = 0 THEN

      SELECT CASE tVal

        CASE 256 + ASC("=")
          opIdx = ii
          opType = 1
          EXIT FOR

        CASE 256 + ASC("<")
          opIdx = ii
          IF ii + 1 <= endIdx THEN
            nxtVal = retTokenVal(lineTokens$(ii + 1))
            IF nxtVal = 256 + ASC(">") THEN
              opType = 6
              opLen = 2
              EXIT FOR
            END IF
            IF nxtVal = 256 + ASC("=") THEN
              opType = 4
              opLen = 2
              EXIT FOR
            END IF
          END IF
          opType = 2
          EXIT FOR

        CASE 256 + ASC(">")
          opIdx = ii
          IF ii + 1 <= endIdx THEN
            nxtVal = retTokenVal(lineTokens$(ii + 1))
            IF nxtVal = 256 + ASC("=") THEN
              opType = 5
              opLen = 2
              EXIT FOR
            END IF
          END IF
          opType = 3
          EXIT FOR

      END SELECT ' tVal

    END IF
  NEXT

  IF opIdx = -1 THEN
    ' No explicit relationship found so we evaluate the statement to see if it is mathematically non-zero
    expr1Res = parseExpression(startIdx, endIdx, 1)
    IF expr1Res = 0 THEN
      parseCondition = 0
      EXIT FUNCTION
    END IF

    IF exprIs.DataType = TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH IN CONDITION", ASIS, 0
      parseCondition = 0
      EXIT FUNCTION
    END IF

    IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
      opMode = MODE_SSE_DOUBLE
      IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
      ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
    END IF

    ' Test if the resulting expression in RAX is zero
    ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)

    IF jumpOnTrue = 1 THEN
      patchPos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
      truePatches(truePatchCount) = patchPos
      truePatchCount = truePatchCount + 1
    END IF

    IF jumpOnFalse = 1 THEN
      patchPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
      falsePatches(falsePatchCount) = patchPos
      falsePatchCount = falsePatchCount + 1
    END IF

    expectedSymType = TYPE_ANY ' Prevent leakage
    parseCondition = 1
    EXIT FUNCTION
  END IF

  IF compileClassicMode = 1 THEN
    rhsType = determineExprType(opIdx + opLen, endIdx)
    IF rhsType = TYPE_STRING THEN
      expectedSymType = TYPE_STRING
    ELSE
      expectedSymType = TYPE_SINGLE
    END IF
  END IF

  expr1Res = parseExpression(startIdx, opIdx - 1, 1)
  IF expr1Res = 0 THEN
    parseCondition = 0
    EXIT FUNCTION
  END IF

  leftDataType = exprIs.DataType

  ' Save LHS to stable hardware stack
  IF leftDataType = TYPE_SINGLE OR leftDataType = TYPE_DOUBLE THEN
    ff = opSSE(SSE_MOVQ_REG_XMM, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
  END IF
  opPushReg 0

  IF compileClassicMode = 1 THEN
    IF leftDataType = TYPE_STRING THEN expectedSymType = TYPE_STRING ELSE expectedSymType = TYPE_SINGLE
  END IF

  expr2Res = parseExpression(opIdx + opLen, endIdx, 1)
  IF expr2Res = 0 THEN
    parseCondition = 0
    EXIT FUNCTION
  END IF

  rightDataType = exprIs.DataType

  ' RHS is currently in RAX (or XMM0)
  ' We need RHS in RBX (or XMM1), and LHS in RAX (or XMM0)

  opPopReg 3 ' Pop LHS into RBX

  IF leftDataType = TYPE_STRING AND rightDataType = TYPE_STRING THEN
    ' String Compare Block
    ' LHS is in RBX (3), RHS is in RAX (0)

    ' Deep String Comparison Block
    ff = genLoadStringDesc(3, 6, 1)
    ff = genLoadStringDesc(0, 7, 2)

    ' cmp rcx, rdx
    ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)
    ' mov r8, rcx
    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)

    ' jle .skip_min
    jmpMinPos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
    ' mov r8, rdx
    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 2, 64)

    ' .skip_min:
    patch8 jmpMinPos

    ' test r8, r8
    ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
    ' je .compare_lengths
    jmpLenPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' push rcx (save LHS length to preserve for later length compare)
    opPushReg 1

    ' mov rcx, r8 (set counter to min length)
    ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)

    ' Explicitly clear the Direction Flag to ensure CMPSB iterates forwards
    opFlag FLAG_CLD

    ' repe cmpsb
    opString STR_CMPS, REP_REP, 8

    ' pop rcx (restore LHS length)
    opPopReg 1

    ' jne .done (if mismatched within min length, flags are perfectly set)
    jmpDonePos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

    ' .compare_lengths:
    patch8 jmpLenPos

    ' cmp rcx, rdx (compare lengths to break ties)
    ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)

    ' .done:
    patch8 jmpDonePos

  ELSE
    ' In Classic Mode, allow mixed floating point mapping without strings
    IF leftDataType = TYPE_STRING OR rightDataType = TYPE_STRING THEN
      throwCompilerError "TYPE MISMATCH IN CONDITION", ASIS, 0
      parseCondition = 0
      EXIT FUNCTION
    END IF

    IF leftDataType = TYPE_SINGLE OR leftDataType = TYPE_DOUBLE OR rightDataType = TYPE_SINGLE OR rightDataType = TYPE_DOUBLE THEN
      ' Float compare
      IF rightDataType = TYPE_SINGLE OR rightDataType = TYPE_DOUBLE THEN
        ' Move RHS from XMM0 to XMM1
        opMode = MODE_SSE_DOUBLE
        IF rightDataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
        ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 0, opMode)
      ELSE
        ' Convert RHS from RAX to XMM1
        ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        rightDataType = TYPE_DOUBLE ' Force to double
      END IF

      IF leftDataType = TYPE_SINGLE OR leftDataType = TYPE_DOUBLE THEN
        ' Restore LHS from RBX directly to XMM0
        ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
      ELSE
        ' Convert LHS from RBX to XMM0
        ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, MODE_SSE_DOUBLE)
        leftDataType = TYPE_DOUBLE ' Force to double
      END IF

      targetMode = MODE_SSE_DOUBLE
      IF leftDataType = TYPE_SINGLE AND rightDataType = TYPE_SINGLE THEN targetMode = MODE_SSE_SINGLE

      ' Promote single to double if needed
      IF leftDataType = TYPE_SINGLE AND targetMode = MODE_SSE_DOUBLE THEN
        ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
      END IF
      IF rightDataType = TYPE_SINGLE AND targetMode = MODE_SSE_DOUBLE THEN
        ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 1, OP_TYPE_REG, 1, MODE_SSE_SINGLE)
      END IF

      ' Compare XMM0 and XMM1
      ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 0, OP_TYPE_REG, 1, targetMode)

    ELSE
      ' Numeric compare
      ' LHS is in RBX (3), RHS is in RAX (0)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 3, OP_TYPE_REG, 0, 64)
    END IF
  END IF

  IF jumpOnTrue = 1 THEN

    IF leftDataType = TYPE_SINGLE OR leftDataType = TYPE_DOUBLE OR rightDataType = TYPE_SINGLE OR rightDataType = TYPE_DOUBLE THEN
      ' UCOMISD exclusively sets unsigned flags, remap conditionals accordingly

      SELECT CASE opType

        CASE 1: condCode = JCC_JE
        CASE 2: condCode = JCC_JB
        CASE 3: condCode = JCC_JA
        CASE 4: condCode = JCC_JBE
        CASE 5: condCode = JCC_JAE
        CASE 6: condCode = JCC_JNE

      END SELECT ' opType

    ELSE
      IF leftDataType = TYPE_STRING AND rightDataType = TYPE_STRING THEN
        ' Unsigned jumps required for comparing raw character value ranges

        SELECT CASE opType

          CASE 1: condCode = JCC_JE
          CASE 2: condCode = JCC_JB
          CASE 3: condCode = JCC_JA
          CASE 4: condCode = JCC_JBE
          CASE 5: condCode = JCC_JAE
          CASE 6: condCode = JCC_JNE

        END SELECT ' opType

      ELSE

        SELECT CASE opType

          CASE 1: condCode = JCC_JE
          CASE 2: condCode = JCC_JL
          CASE 3: condCode = JCC_JG
          CASE 4: condCode = JCC_JLE
          CASE 5: condCode = JCC_JGE
          CASE 6: condCode = JCC_JNE

        END SELECT ' opType

      END IF
    END IF

    patchPos = opJcc(condCode, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
    truePatches(truePatchCount) = patchPos
    truePatchCount = truePatchCount + 1
  END IF

  IF jumpOnFalse = 1 THEN

    IF leftDataType = TYPE_SINGLE OR leftDataType = TYPE_DOUBLE OR rightDataType = TYPE_SINGLE OR rightDataType = TYPE_DOUBLE THEN

      SELECT CASE opType

        CASE 1: condCode = JCC_JNE
        CASE 2: condCode = JCC_JAE
        CASE 3: condCode = JCC_JBE
        CASE 4: condCode = JCC_JA
        CASE 5: condCode = JCC_JB
        CASE 6: condCode = JCC_JE

      END SELECT ' opType

    ELSE
      IF leftDataType = TYPE_STRING AND rightDataType = TYPE_STRING THEN

        SELECT CASE opType

          CASE 1: condCode = JCC_JNE
          CASE 2: condCode = JCC_JAE
          CASE 3: condCode = JCC_JBE
          CASE 4: condCode = JCC_JA
          CASE 5: condCode = JCC_JB
          CASE 6: condCode = JCC_JE

        END SELECT ' opType

      ELSE

        SELECT CASE opType

          CASE 1: condCode = JCC_JNE
          CASE 2: condCode = JCC_JGE
          CASE 3: condCode = JCC_JLE
          CASE 4: condCode = JCC_JG
          CASE 5: condCode = JCC_JL
          CASE 6: condCode = JCC_JE

        END SELECT ' opType

      END IF
    END IF

    patchPos = opJcc(condCode, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
    falsePatches(falsePatchCount) = patchPos
    falsePatchCount = falsePatchCount + 1
  END IF

  expectedSymType = TYPE_ANY ' Prevent leakage
  parseCondition = 1

END FUNCTION ' parseCondition

''''''''''''''''''''''''
FUNCTION parseExpression (startIdx, endIdx, allowImplicit)

  DIM rootNode AS LONG
  DIM res AS LONG
  DIM savedAstNodeCount AS LONG

  savedAstNodeCount = astNodeCount
  rootNode = buildAstExpression(startIdx, endIdx)

  IF rootNode = -1 THEN
    astNodeCount = savedAstNodeCount
    parseExpression = 0
    EXIT FUNCTION
  END IF

  res = emitAstNode(rootNode, allowImplicit)

  astNodeCount = savedAstNodeCount
  parseExpression = res

END FUNCTION ' parseExpression

''''''''''''''''''''''''
FUNCTION parseFactor (startIdx, endIdx, allowImplicit)

  ' Handles single tokens, unary minus, functions, and parentheses

  ' Routes between literals, variables, and built-in functions
  ' Built-ins act like standalone mini-commands parsing syntax and emitting assembly directly
  ' They must return results in RAX or XMM0 so math layers can process them

  DIM dataSlot AS LONG
  DIM opMode AS LONG
  DIM exprXRes AS LONG
  DIM exprYRes AS LONG
  DIM axIdx AS LONG
  DIM elemSize AS LONG
  DIM lenIdx AS LONG
  DIM emptyDescIdx AS LONG

  tempSuccess = 0

  '''' 1. SINGLE TOKEN COMMANDS (INKEYF, INKEY)
  IF startIdx = endIdx THEN
    IF retTokenVal(lineTokens$(startIdx)) = TOK_INKEYF OR (retTokenVal(lineTokens$(startIdx)) = TOK_INKEY AND compileHasGraphics = 0) THEN

      inkeyfScratchIdx = resolveSymbol("!INKEYFSCR" + cTrNum$(tempVarCounter) + "$")
      tempVarCounter = tempVarCounter + 1
      IF inkeyfScratchIdx = -1 THEN
        parseFactor = 0
        EXIT FUNCTION
      END IF

      ' Allocate from Temp Heap
      ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' Save heap start ptr
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

      ' mov r15, 8
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)

      inkeyLoopStart = emitPos

      ' mov rcx, r15
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)
      ' mov r13, rsp
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_REG, 4, 64)
      ' and rsp, -16
      ff = opALU(ALU_AND, OP_TYPE_REG, 4, OP_TYPE_IMM, -16, 64)
      ' sub rsp, 32
      ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)

      ' call GetAsyncKeyState
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)

      ' mov rsp, r13
      ff = opMov(OP_TYPE_REG, 4, OP_TYPE_REG, 13, 64)

      ' test ax, &H8000
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)

      ' jz .next
      jmpNextPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ' sub rdi, 1
      ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_IMM, 1, 64)

      ' Quick mapping for Numpad keys (96-105 to 48-57)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 96, 8)
      jmpSkipNumpadA1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 105, 8)
      jmpSkipNumpadA2 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 15, OP_TYPE_IMM, 48, 8)
      patch8 jmpSkipNumpadA1
      patch8 jmpSkipNumpadA2

      ' Quick mapping for arrow keys (Translates VK codes 37-40 to character values 52, 56, 54, 50)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 37, 8)
      jmpNotLeft = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 52, 8)
      jmpMapDone1 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotLeft

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 38, 8)
      jmpNotUp = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 56, 8)
      jmpMapDone2 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotUp

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 39, 8)
      jmpNotRight = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 54, 8)
      jmpMapDone3 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotRight

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 40, 8)
      jmpNotDown = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 50, 8)
      jmpMapDone4 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotDown

      patch8 jmpMapDone1
      patch8 jmpMapDone2
      patch8 jmpMapDone3
      patch8 jmpMapDone4

      ' mov [rdi], r15b
      ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 15, 8)
      ' mov r14, rdi
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      ' mov rcx, 1
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)

      ' jmp .done
      jmpDonePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ' .next:
      patch8 jmpNextPos

      ' inc r15
      opIncReg 15, 64

      ' cmp r15, 255
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)

      ' jl .loop
      ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, inkeyLoopStart, JCC_TYPE_NEAR)

      ' Empty return
      ' mov rcx, 0
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 0, 64)

      ' .done:
      patch8 jmpDonePos

      ' Update Temp Heap Ptr
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 7, 64, TEMP_HEAP_VAR_IDX)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' Update Descriptor
      ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, inkeyfScratchIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' mov [rax], r14 (DataAddress)
      ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_REG, 14, 64)
      ' mov [rax + 8], rcx (Length)
      ff = opMov(OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), OP_TYPE_REG, 1, 64)

      exprIs.DataType = TYPE_STRING
      exprIs.IsTemp = 1
      parseFactor = 1
      EXIT FUNCTION
    END IF

    IF retTokenVal(lineTokens$(startIdx)) = TOK_INKEY AND compileHasGraphics = 1 THEN

      inkeyScratchIdx = resolveSymbol("!INKEYSCR" + cTrNum$(tempVarCounter) + "$")
      tempVarCounter = tempVarCounter + 1
      IF inkeyScratchIdx = -1 THEN
        parseFactor = 0
        EXIT FUNCTION
      END IF

      ' Allocate from Temp Heap
      ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' Save heap start ptr
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

      ' lea rax, [rip + KbdHeadBase]
      addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -5, 0
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' mov r10d, [rax]
      ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG, 0, 32)

      ' lea rdx, [rip + KbdTailBase]
      addPatch PATCH_GFX, opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64), -6, 0
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' mov r11d, [rdx]
      ff = opMov(OP_TYPE_REG, 11, OP_TYPE_MEM_REG, 2, 32)

      ' cmp r10d, r11d
      ff = opALU(ALU_CMP, OP_TYPE_REG, 10, OP_TYPE_REG, 11, 32)

      ' je .empty
      jmpEmptyPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ' lea rcx, [rip + KbdBufBase]
      addPatch PATCH_GFX, opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64), -7, 0
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' movzx r8d, byte [rcx + r11]
      ff = opMov_SIB(0, OP_TYPE_REG, 8, 1, 11, 1, 0, MODE_MOVZX32_8)

      ' inc r11d
      opIncReg 11, 32

      ' and r11d, 255
      ff = opALU(ALU_AND, OP_TYPE_REG, 11, OP_TYPE_IMM, 255, 32)

      ' mov [rdx], r11d
      ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 11, 32)

      ' sub rdi, 1
      ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_IMM, 1, 64)

      ' mov [rdi], r8b
      ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 8, 8)

      ' mov r14, rdi
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

      ' mov rcx, 1
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)

      ' jmp .done
      jmpDonePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ' .empty:
      patch8 jmpEmptyPos

      ' mov rcx, 0
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 0, 64)

      ' .done:
      patch8 jmpDonePos

      ' Update Temp Heap Ptr
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 7, 64, TEMP_HEAP_VAR_IDX)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' Update Descriptor
      ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, inkeyScratchIdx)
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

      ' mov [rax], r14 (DataAddress)
      ff = opMov(OP_TYPE_MEM_REG, 0, OP_TYPE_REG, 14, 64)
      ' mov [rax + 8], rcx (Length)
      ff = opMov(OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), OP_TYPE_REG, 1, 64)

      exprIs.DataType = TYPE_STRING
      exprIs.IsTemp = 1
      parseFactor = 1
      EXIT FUNCTION
    END IF
  END IF

  '''' 2. IDENTIFIERS (Variables, Arrays, Function Calls, UDTs)
  vTok$ = lineTokens$(startIdx)
  IF retTokenVal(vTok$) = 0 AND LEN(vTok$) > 0 THEN
    firstChar$ = LEFT$(vTok$, 1)
    IF (firstChar$ >= "A" AND firstChar$ <= "Z") OR (firstChar$ >= "a" AND firstChar$ <= "z") OR firstChar$ = "!" THEN

      vName$ = UCASE$(vTok$)

      hasIndex = 0
      closeParenIdx = -1
      tokIdx = startIdx + 1

      IF tokIdx <= endIdx THEN
        IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
          hasIndex = 1
          closeParenIdx = findMatchingParen(tokIdx, endIdx)
          IF closeParenIdx = -1 THEN
            throwCompilerError "MISSING )", ASIS, 0
            parseFactor = 0: EXIT FUNCTION
          END IF
          tokIdx = closeParenIdx + 1
        END IF
      END IF

      hasField = 0
      IF tokIdx <= endIdx THEN
        IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(".") THEN hasField = 1
      END IF

      ' Do not duck-type explicitly complex arrays or UDTs
      IF hasIndex = 1 OR hasField = 1 THEN expectedSymType = TYPE_ANY

      vIdx = findSymbol(vName$)
      IF vIdx = -1 THEN
        IF allowImplicit = 0 THEN
          throwCompilerError "UNDECLARED VARIABLE OR FUNCTION '" + vName$ + "'", ASIS, 0
          parseFactor = 0
          EXIT FUNCTION
        ELSE
          vIdx = resolveSymbol(vName$)
          IF vIdx = -1 THEN parseFactor = 0: EXIT FUNCTION
        END IF
      END IF

      subIdx = symbols(vIdx).SubIndex

      IF subIdx <> -1 THEN
        ' Function Call
        IF tokIdx <= endIdx THEN
          throwCompilerError "UNEXPECTED TOKENS AFTER FUNCTION", ASIS, 0
          parseFactor = 0: EXIT FUNCTION
        END IF

        argIdx = 0
        IF hasIndex = 1 AND closeParenIdx > startIdx + 2 THEN
          aStart = startIdx + 2
          DO WHILE aStart < closeParenIdx
            aEnd = findNextTokenAtDepth0(aStart, closeParenIdx - 1, 256 + ASC(","))
            IF aEnd = -1 THEN aEnd = closeParenIdx

            IF argIdx >= subs(subIdx).ArgCount THEN
              throwCompilerError "TOO MANY ARGS FOR " + vName$, ASIS, 0
              parseFactor = 0: EXIT FUNCTION
            END IF

            exprRes = parseExpression(aStart, aEnd - 1, allowImplicit)
            IF exprRes = 0 THEN parseFactor = 0: EXIT FUNCTION

            targetVarIdx = subArgVarIdx(subIdx, argIdx)

            IF symbols(targetVarIdx).IsArray = 2 THEN
              IF exprIs.DataType = TYPE_STRING AND symbols(targetVarIdx).DataType <> TYPE_STRING THEN
                throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
                parseFactor = 0: EXIT FUNCTION
              END IF
              IF exprIs.DataType <> TYPE_STRING AND symbols(targetVarIdx).DataType = TYPE_STRING THEN
                throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
                parseFactor = 0: EXIT FUNCTION
              END IF

              ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, targetVarIdx)
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION
            ELSE
              IF symbols(targetVarIdx).DataType = TYPE_STRING THEN
                IF exprIs.DataType <> TYPE_STRING THEN
                  throwCompilerError "TYPE MISMATCH ARG", ASIS, 0
                  parseFactor = 0
                  EXIT FUNCTION
                END IF
                ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
                ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, targetVarIdx)
                IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                  parseFactor = 0
                  EXIT FUNCTION
                END IF
                addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
                IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
                  parseFactor = 0
                  EXIT FUNCTION
                END IF
              ELSE
                IF exprIs.DataType = TYPE_STRING THEN
                  throwCompilerError "TYPE MISMATCH ARG", ASIS, 0
                  parseFactor = 0
                  EXIT FUNCTION
                END IF
                targetType = symbols(targetVarIdx).DataType
                IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
                  IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
                    ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
                    exprIs.DataType = TYPE_DOUBLE
                  END IF
                  IF exprIs.DataType = TYPE_DOUBLE AND targetType = TYPE_SINGLE THEN
                    ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
                  END IF
                  IF exprIs.DataType = TYPE_SINGLE AND targetType = TYPE_DOUBLE THEN
                    ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
                  END IF
                  opMode = MODE_SSE_DOUBLE
                  IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
                  ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, opMode, targetVarIdx)
                ELSE
                  IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
                    opMode = MODE_SSE_DOUBLE
                    IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
                    ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
                  END IF
                  ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, targetVarIdx)
                END IF
                IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION
              END IF
            END IF

            argIdx = argIdx + 1
            aStart = aEnd + 1
          LOOP
        END IF

        IF argIdx < subs(subIdx).ArgCount THEN
          throwCompilerError "TOO FEW ARGS FOR " + vName$, ASIS, 0
          parseFactor = 0: EXIT FUNCTION
        END IF

        addPatchStr PATCH_CALL, opCall(0, CALLMODE_REL32), vName$
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION

        retVarIdx = subs(subIdx).ReturnVarIdx
        exprIs.IsTemp = 0
        IF retVarIdx <> -1 THEN
          exprIs.DataType = symbols(retVarIdx).DataType

          SELECT CASE symbols(retVarIdx).DataType

            CASE TYPE_SINGLE
              ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_SINGLE, retVarIdx)

            CASE TYPE_DOUBLE
              ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_DOUBLE, retVarIdx)

            CASE ELSE
              ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, retVarIdx)

          END SELECT ' DataType

          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION
        ELSE
          ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
          exprIs.DataType = TYPE_LONG
        END IF
        parseFactor = 1
        EXIT FUNCTION
      END IF

      IF vIdx <> -1 THEN
        ' Variable, Array, or UDT
        IF hasField = 1 THEN
          tokIdx = tokIdx + 1
          IF tokIdx > endIdx THEN
            throwCompilerError "EXPECTED FIELD NAME", ASIS, 0
            parseFactor = 0: EXIT FUNCTION
          END IF
          fieldName$ = UCASE$(lineTokens$(tokIdx))
          tokIdx = tokIdx + 1

          IF symbols(vIdx).DataType <> TYPE_UDT THEN
            throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
            parseFactor = 0: EXIT FUNCTION
          END IF

          uIdx = symbols(vIdx).UDTIndex
          fFound = 0
          FOR f = 0 TO udts(uIdx).FieldCount - 1
            IF RTRIM$(udtFields(uIdx, f).FieldName) = fieldName$ THEN
              udtOffset = udtFields(uIdx, f).Offset
              targetType = udtFields(uIdx, f).DataType
              fFound = 1
              EXIT FOR
            END IF
          NEXT
          IF fFound = 0 THEN
            throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
            parseFactor = 0: EXIT FUNCTION
          END IF
        ELSE
          targetType = symbols(vIdx).DataType
        END IF

        IF tokIdx <= endIdx THEN
          throwCompilerError "MALFORMED FACTOR", ASIS, 0
          parseFactor = 0: EXIT FUNCTION
        END IF

        IF hasIndex = 1 THEN
          commaIdx = findNextTokenAtDepth0(startIdx + 2, closeParenIdx - 1, 256 + ASC(","))

          IF commaIdx = -1 THEN
            ' Handle Empty Parens logic properly
            IF startIdx + 2 = closeParenIdx THEN
              ' Emits pointer directly if it's an array root pointer request
              IF symbols(vIdx).IsArray = 2 THEN
                ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, vIdx)
              ELSE
                ff = genSymbolRouteLea(0, vIdx)
              END IF
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseFactor = 0: EXIT FUNCTION
              exprIs.DataType = targetType
              exprIs.IsTemp = 0
              parseFactor = 1
              EXIT FUNCTION
            END IF

            IF symbols(vIdx).Size2 > 0 AND symbols(vIdx).IsArray <> 2 THEN
              throwCompilerError "EXPECTED 2D ARRAY", ASIS, 0
              parseFactor = 0: EXIT FUNCTION
            END IF

            exprXRes = parseExpression(startIdx + 2, closeParenIdx - 1, allowImplicit)
            IF exprXRes = 0 THEN
              parseFactor = 0
              EXIT FUNCTION
            END IF

            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "ARRAY INDEX MUST BE NUMERIC", ASIS, 0
              parseFactor = 0
              EXIT FUNCTION
            END IF

            IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
              opMode = MODE_SSE_DOUBLE
              IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF
          ELSE
            IF symbols(vIdx).Size2 = 0 AND symbols(vIdx).IsArray <> 2 THEN
              throwCompilerError "EXPECTED 1D ARRAY", ASIS, 0
              parseFactor = 0
              EXIT FUNCTION
            END IF

            exprXRes = parseExpression(startIdx + 2, commaIdx - 1, allowImplicit)
            IF exprXRes = 0 THEN parseFactor = 0: EXIT FUNCTION

            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "ARRAY INDEX MUST BE NUMERIC", ASIS, 0
              parseFactor = 0
              EXIT FUNCTION
            END IF

            IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
              opMode = MODE_SSE_DOUBLE
              IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF

            opPushReg 0 ' Push X

            exprYRes = parseExpression(commaIdx + 1, closeParenIdx - 1, allowImplicit)
            IF exprYRes = 0 THEN parseFactor = 0: EXIT FUNCTION

            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "ARRAY INDEX MUST BE NUMERIC", ASIS, 0
              parseFactor = 0: EXIT FUNCTION
            END IF

            IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
              opMode = MODE_SSE_DOUBLE
              IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF

            opPopReg 3 ' X in RBX

            ' Multiply Y (RAX) by AX (Stride X)
            axIdx = resolveSymbol("!" + RTRIM$(symbols(vIdx).RecordName) + "_AX")
            ff = genSymbolRouteMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64, axIdx)
            ff = opImul(0, OP_TYPE_REG, 8, 0, MODE_IMUL64_REG) ' RAX = Y * AX

            ' Add X
            ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64) ' RAX = (Y * AX) + X
          END IF

          ' Multiply RAX by element size
          elemSize = 8
          SELECT CASE symbols(vIdx).DataType

            CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
            CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
            CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
            CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
            CASE TYPE_STRING
              IF hasField = 0 THEN
                lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
                IF floatVarData(lenIdx) > 0 THEN
                  elemSize = floatVarData(lenIdx)
                ELSE
                  elemSize = 8
                END IF
              END IF

          END SELECT ' symbols(vIdx).DataType

          IF elemSize <> 1 THEN
            ff = opImul(0, OP_TYPE_REG, 0, elemSize, MODE_IMUL64_IMM32)
          END IF
        END IF

        ' Load Base into RDX (2)
        IF symbols(vIdx).IsArray = 2 THEN
          ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64, vIdx)
        ELSE
          ff = genSymbolRouteLea(2, vIdx)
        END IF

        IF hasIndex = 1 THEN
          ' Add Array Offset (RAX) to Base Address (RDX)
          ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)
        END IF

        IF udtOffset > 0 THEN
          ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, udtOffset, 64)
        END IF

        IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
          IF targetType = TYPE_SINGLE THEN
            ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 32)
          ELSE
            ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 64)
          END IF
          ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        ELSE

          SELECT CASE targetType

            CASE TYPE_BYTE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVSX64_8)
            CASE TYPE_UBYTE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVZX64_8)
            CASE TYPE_INTEGER: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVSX64_16)
            CASE TYPE_UINTEGER: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVZX64_16)
            CASE TYPE_LONG: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVSXD)
            CASE TYPE_ULONG, TYPE_SINGLE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 32)
            CASE TYPE_STRING
              IF symbols(vIdx).IsLocal = 1 AND symbols(vIdx).IsShared = 0 AND symbols(vIdx).IsArray = 0 AND hasIndex = 0 AND hasField = 0 THEN
                ' For local standalone strings, the address calculated in RDX IS the descriptor pointer!
                ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 2, 64)
              ELSE
                ' For all other strings (Globals, Arrays, UDT fields), we must dereference the 8-byte pointer to find the descriptor
                ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 64)
              END IF

              ' Protect against uninitialized dynamic string pointers
              ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
              jmpSkipNull = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
              emptyDescIdx = resolveSymbol("!EMPTY_DESC$")
              ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, emptyDescIdx)
              patch8 jmpSkipNull
            CASE ELSE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 64)

          END SELECT ' targetType

        END IF

        exprIs.DataType = targetType
        exprIs.IsTemp = 0

        parseFactor = 1
        EXIT FUNCTION
      END IF
    END IF
  END IF

  '''' 3. NUMERIC/STRING LITERALS
  IF startIdx = endIdx THEN
    emitLoadValue lineTokens$(startIdx)
    parseFactor = 1
    EXIT FUNCTION
  END IF

  '''' 4. UNARY MINUS AND NOT
  IF startIdx < endIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx))
    IF tVal = 256 + ASC("-") OR tVal = TOK_NOT THEN
      exprRes = parseFactor(startIdx + 1, endIdx, allowImplicit)
      IF exprRes = 0 THEN
        parseFactor = 0
        EXIT FUNCTION
      END IF
      IF exprIs.DataType = TYPE_STRING THEN
        throwCompilerError "TYPE MISMATCH", ASIS, 0
        parseFactor = 0
        EXIT FUNCTION
      END IF

      IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
        ' Logic operators and bitwise logic are always resolved as Integers
        opMode = MODE_SSE_DOUBLE
        IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
        ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
        exprIs.DataType = TYPE_LONG
      END IF

      IF tVal = 256 + ASC("-") THEN
        ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)
      ELSE
        ff = opUnary(UNARY_NOT, OP_TYPE_REG, 0, 64)
      END IF

      parseFactor = 1
      EXIT FUNCTION
    END IF
  END IF

  '''' 5. PARENTHESES ENCLOSURE
  stripParens = 0
  IF retTokenVal(lineTokens$(startIdx)) = 256 + ASC("(") THEN
    IF findMatchingParen(startIdx, endIdx) = endIdx THEN
      stripParens = 1
    END IF
  END IF

  IF stripParens = 1 THEN
    exprRes = parseExpression(startIdx + 1, endIdx - 1, allowImplicit)
    parseFactor = exprRes
    EXIT FUNCTION
  END IF

  '''' 6. INTRINSIC FUNCTION DISPATCHER
  tVal = retTokenVal(lineTokens$(startIdx))
  isIntrinsic = 0
  FOR ii = 0 TO intrinsicCount - 1
    IF tVal = intrinsicDefs(ii).TokenVal THEN
      isIntrinsic = 1
      EXIT FOR
    END IF
  NEXT

  IF isIntrinsic = 1 THEN
    tempSuccess = parseIntrinsic(startIdx, endIdx, allowImplicit)
    parseFactor = tempSuccess
    EXIT FUNCTION
  END IF

  throwCompilerError "MALFORMED EXPRESSION", ASIS, 0
  parseFactor = 0

END FUNCTION ' parseFactor

''''''''''''''''''''''''
FUNCTION parseImplicitAssign (startIdx)

  ' If the line starts with an identifier (variables, arrays, function names, labels)
  ' this function acts as a probe. It scans forward, cleanly skipping over array indices
  '  (1, 2) and UDT fields .X, looking for an = sign. If it finds one, it
  '  confidently hands the line over to parseAssign. If it doesn't, it returns -1
  '  to tell parseStatement to try evaluating it as a subroutine call instead.

  DIM tempSuccess AS LONG
  DIM checkIdx AS LONG
  DIM pDepth AS LONG
  DIM ii AS LONG
  DIM tVal AS LONG

  tempSuccess = -1
  checkIdx = startIdx + 1

  ' Fast-fail lookahead: Skip over any array parentheses
  IF checkIdx < lineTokenCount THEN
    IF retTokenVal(lineTokens$(checkIdx)) = 256 + ASC("(") THEN
      pDepth = 0
      FOR ii = checkIdx TO lineTokenCount - 1
        tVal = retTokenVal(lineTokens$(ii))
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
    IF retTokenVal(lineTokens$(checkIdx)) = 256 + ASC(".") THEN
      checkIdx = checkIdx + 2 ' Skip the dot and the field name
    END IF
  END IF

  ' Check if the resulting token is an equals sign
  IF checkIdx < lineTokenCount THEN
    IF retTokenVal(lineTokens$(checkIdx)) = 256 + ASC("=") THEN
      ' We found an equals sign! This is definitively an assignment.
      assignRes = parseAssign(startIdx)
      IF assignRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "ASSIGN FAILED", ASIS, 0
      ELSE
        tempSuccess = assignRes
      END IF
      parseImplicitAssign = tempSuccess
      EXIT FUNCTION
    END IF
  END IF

  ' No equals sign found. Return -1 so the parser can try treating it as a SUB call.
  parseImplicitAssign = tempSuccess

END FUNCTION ' parseImplicitAssign

''''''''''''''''''''''''
FUNCTION parseIntrinsic (startIdx, endIdx, allowImplicit)

  ' Compiles built-in functions that act like standalone mini-commands
  ' Logic parses their complex syntax and emits the specific assembly required
  ' Results land in RAX or XMM0 so math layers can process them

  ' Functions like CHR$, LEN, MID$, and ASC exist solely to transform data or fetch a state and return a result to be used by a Verb
  ' parseIntrinsic/Ex isn't called unless a command like PRINT comes first which needs data

  tempSuccess = 0
  tVal = retTokenVal(lineTokens$(startIdx))

  SELECT CASE tVal

    CASE TOK_STR
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          ff = genForceNumericIntEx(startIdx + 2, endIdx - 1, allowImplicit, "STR$ REQUIRES NUMERIC")
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION
          DIM rtrimScratchIdx AS INTEGER
          strScratchIdx = resolveSymbol("!STRSCR" + cTrNum$(t.TempCounter) + "$")
          t.TempCounter = t.TempCounter + 1
          IF strScratchIdx = -1 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ' Allocate 32 bytes from Temp Heap
          ff = genAllocTempMemory(OP_TYPE_IMM, 32, 7)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          ' R10 will be our writing pointer (start at end of buffer)
          ' mov r10, rdi
          ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 7, 64)
          ' add r10, 31
          ff = opALU(ALU_ADD, OP_TYPE_REG, 10, OP_TYPE_IMM, 31, 64)

          ' Save end pointer to R14
          ' mov r14, r10
          ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 10, 64)

          ' xor r12, r12 (Sign flag: 0 = positive, 1 = negative)
          ff = opALU(ALU_XOR, OP_TYPE_REG, 12, OP_TYPE_REG, 12, 64)
          ' test rax, rax
          ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
          ' jns .positive
          jmpPos = opJcc(JCC_JNS, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' inc r12
          opIncReg 12, 64
          ' neg rax
          ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)

          ' .positive:
          patch8 jmpPos

          ' mov r11, 10
          ff = opMov(OP_TYPE_REG, 11, OP_TYPE_IMM, 10, 64)

          itoaLoopStartStr = emitPos
          ' xor rdx, rdx
          ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)
          ' div r11
          ff = opUnary(UNARY_DIV, OP_TYPE_REG, 11, 64)
          ' add dl, 48
          ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, 48, 8)
          ' dec r10
          opDecReg 10, 64
          ' mov [r10], dl
          ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 2, 8)
          ' test rax, rax
          ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
          ' jnz itoaLoopStartStr
          ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, itoaLoopStartStr, JCC_TYPE_SHORT)

          ' dec r10
          opDecReg 10, 64

          ' test r12, r12
          ff = opTest(OP_TYPE_REG, 12, OP_TYPE_REG, 12, 64)
          ' jz .add_space
          jmpSpace = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' mov byte [r10], 45 '-'
          ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_IMM, 45, 8)
          ' jmp .done
          jmpDoneStr = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' .add_space:
          patch8 jmpSpace
          ' mov byte [r10], 32 ' '
          ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_IMM, 32, 8)

          ' .done:
          patch8 jmpDoneStr

          ' Calculate Length: R8 = R14 - R10
          ' mov r8, r14
          ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 14, 64)
          ' sub r8, r10
          ff = opALU(ALU_SUB, OP_TYPE_REG, 8, OP_TYPE_REG, 10, 64)

          ' Update Descriptor
          ff = genUpdateStringDescriptor(strScratchIdx, 10, 8)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          exprIs.DataType = TYPE_STRING
          exprIs.IsTemp = 1
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_VAL
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "VAL REQUIRES STRING", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ' Load descriptor: RSI = Data Address, RCX = Length
          ff = genLoadStringDesc(0, 6, 1)

          ' xor eax, eax
          ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
          ' xor edi, edi (sign flag)
          ff = opALU(ALU_XOR, OP_TYPE_REG, 7, OP_TYPE_REG, 7, 32)

          skipSpaceStart = emitPos
          ' test rcx, rcx
          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          ' jz .num_done
          jmpNumDone1Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

          ' cmp byte [rsi], 32
          ff = opALU(ALU_CMP, OP_TYPE_MEM_REG, 6, OP_TYPE_IMM, 32, 8)
          ' jne .check_sign
          jmpCheckSignPos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' inc rsi
          opIncReg 6, 64
          ' dec rcx
          opDecReg 1, 64
          ' jmp skipSpaceStart
          ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, skipSpaceStart, JCC_TYPE_SHORT)

          ' .check_sign:
          patch8 jmpCheckSignPos

          ' cmp byte [rsi], 45 '-'
          ff = opALU(ALU_CMP, OP_TYPE_MEM_REG, 6, OP_TYPE_IMM, 45, 8)
          ' jne .num_loop
          jmpNumLoopPos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' inc rdi (sign flag = 1)
          opIncReg 7, 64
          ' inc rsi
          opIncReg 6, 64
          ' dec rcx
          opDecReg 1, 64

          numLoopStart = emitPos
          patch8 jmpNumLoopPos

          ' test rcx, rcx
          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          ' jz .num_done
          jmpNumDone2Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

          ' movzx rdx, byte [rsi]
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG, 6, MODE_MOVZX64_8)

          ' sub dl, 48
          ff = opALU(ALU_SUB, OP_TYPE_REG, 2, OP_TYPE_IMM, 48, 8)
          ' cmp dl, 9
          ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 9, 8)
          ' ja .num_skip
          jmpNumSkipPos = opJcc(JCC_JA, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' imul rax, 10
          ff = opImul(0, OP_TYPE_REG, 0, 10, MODE_IMUL64_IMM)
          ' add rax, rdx
          ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG_ALT, 2, 64)

          ' .num_skip:
          patch8 jmpNumSkipPos
          ' inc rsi
          opIncReg 6, 64
          ' dec rcx
          opDecReg 1, 64
          ' jmp .num_loop
          ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, numLoopStart, JCC_TYPE_NEAR)

          patch32 jmpNumDone1Pos, emitPos - (jmpNumDone1Pos + 4)
          patch32 jmpNumDone2Pos, emitPos - (jmpNumDone2Pos + 4)

          ' test rdi, rdi
          ff = opTest(OP_TYPE_REG, 7, OP_TYPE_REG, 7, 64)
          ' jz .num_store
          jmpNumStorePos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' neg rax
          ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)

          ' .num_store:
          patch8 jmpNumStorePos

          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 0
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_LTRIM
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "LTRIM$ REQUIRES STRING", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          DIM ltrimScratchIdx AS INTEGER
          ltrimScratchIdx = resolveSymbol("!LTRIMSCR" + cTrNum$(t.TempCounter) + "$")
          t.TempCounter = t.TempCounter + 1
          IF ltrimScratchIdx = -1 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ff = genLoadStringDesc(0, 12, 13)

          ' RCX = Length, RSI = Data Ptr
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)
          ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)

          ltrimLoopStart = emitPos
          ' test rcx, rcx
          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          ' jle .done
          jmpDonePos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' movzx r8d, byte [rsi]
          ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 6, MODE_MOVZX32_8)

          ' cmp r8d, 32
          ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 32, 32)
          ' je .is_space
          jmpIsSpace1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' cmp r8d, 9
          ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 9, 32)
          ' jne .done
          jmpNotSpace = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' .is_space:
          patch8 jmpIsSpace1

          ' inc rsi
          opIncReg 6, 64
          ' dec rcx
          opDecReg 1, 64
          ' jmp .loop
          ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, ltrimLoopStart, JCC_TYPE_SHORT)

          ' .done:
          patch8 jmpDonePos
          patch8 jmpNotSpace

          ' Update Descriptor
          ff = genUpdateStringDescriptor(ltrimScratchIdx, 6, 1)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          exprIs.DataType = TYPE_STRING
          exprIs.IsTemp = 1
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_RTRIM
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "RTRIM$ REQUIRES STRING", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          rtrimScratchIdx = resolveSymbol("!RTRIMSCR" + cTrNum$(t.TempCounter) + "$")
          t.TempCounter = t.TempCounter + 1
          IF rtrimScratchIdx = -1 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ff = genLoadStringDesc(0, 12, 13)

          ' RCX = Length, RSI = Data Ptr
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)
          ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)

          rtrimLoopStart = emitPos
          ' test rcx, rcx
          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          ' jle .done
          jmpRDonePos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' Calculate ptr to last char: rdx = rsi + rcx - 1
          ' mov rdx, rsi
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 6, 64)
          ' add rdx, rcx
          ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_REG, 1, 64)
          ' dec rdx
          opDecReg 2, 64

          ' movzx r8d, byte [rdx]
          ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 2, MODE_MOVZX32_8)

          ' cmp r8d, 32
          ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 32, 32)
          ' je .is_space
          jmpRIsSpace1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' cmp r8d, 9
          ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 9, 32)
          ' jne .done
          jmpRNotSpace = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' .is_space:
          patch8 jmpRIsSpace1

          ' dec rcx
          opDecReg 1, 64
          ' jmp .loop
          ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, rtrimLoopStart, JCC_TYPE_SHORT)

          ' .done:
          patch8 jmpRDonePos
          patch8 jmpRNotSpace

          ' Update Descriptor
          ff = genUpdateStringDescriptor(rtrimScratchIdx, 6, 1)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          exprIs.DataType = TYPE_STRING
          exprIs.IsTemp = 1
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_MID
      IF startIdx + 5 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          comma1 = findNextTokenAtDepth0(startIdx + 2, endIdx - 1, 256 + ASC(","))
          comma2 = -1
          IF comma1 <> -1 THEN
            comma2 = findNextTokenAtDepth0(comma1 + 1, endIdx - 1, 256 + ASC(","))
          END IF

          IF comma1 <> -1 THEN
            IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
            expr1Res = parseExpression(startIdx + 2, comma1 - 1, allowImplicit)
            IF expr1Res = 0 THEN parseIntrinsic = 0: EXIT FUNCTION
            IF exprIs.DataType <> TYPE_STRING THEN
              throwCompilerError "MID$ ARG 1 MUST BE STRING", ASIS, 0
              parseIntrinsic = 0: EXIT FUNCTION
            END IF
            opPushReg 0

            IF comma2 <> -1 THEN
              IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              ff = genForceNumericIntEx(comma1 + 1, comma2 - 1, allowImplicit, "MID$ ARG 2 MUST BE NUMERIC")
              IF ff = 0 THEN
                parseIntrinsic = 0
                EXIT FUNCTION
              END IF
              opPushReg 0

              IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              ff = genForceNumericIntEx(comma2 + 1, endIdx - 1, allowImplicit, "MID$ ARG 3 MUST BE NUMERIC")
              IF ff = 0 THEN
                parseIntrinsic = 0
                EXIT FUNCTION
              END IF
              opPushReg 0
            ELSE
              IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              ff = genForceNumericIntEx(comma1 + 1, endIdx - 1, allowImplicit, "MID$ ARG 2 MUST BE NUMERIC")
              IF ff = 0 THEN
                parseIntrinsic = 0
                EXIT FUNCTION
              END IF
              opPushReg 0

              ' Push a very large length for the missing 3rd arg
              ff = opMov(0, 0, 0, &H7FFFFFFF, MODE_IMM64)
              opPushReg 0
            END IF

            scratchIdx = resolveSymbol("!MIDSCR" + cTrNum$(t.TempCounter) + "$")
            t.TempCounter = t.TempCounter + 1
            IF scratchIdx = -1 THEN parseIntrinsic = 0: EXIT FUNCTION

            ' pop r8 (requested length)
            opPopReg 8
            ' pop rdx (start index)
            opPopReg 2
            ' pop rax (string descriptor ptr)
            opPopReg 0

            ff = genLoadStringDesc(0, 6, 1)

            ' dec rdx (Make index 0-based)
            opDecReg 2, 64
            ' test rdx, rdx
            ff = opTest(OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)

            ' jns +3
            jmpSkipXorPos = opJcc(JCC_JNS, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' xor rdx, rdx
            ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)

            patch8 jmpSkipXorPos

            ' cmp rdx, rcx
            ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_REG_ALT, 1, 64)

            ' jl +3
            jmpSkipMovPos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' mov rdx, rcx
            ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 1, 64)

            patch8 jmpSkipMovPos

            ' add rsi, rdx
            ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_REG_ALT, 2, 64)

            ' sub rcx, rdx (RCX = remaining length)
            ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)

            ' cmp rcx, r8
            ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG_ALT, 8, 64)

            ' jge +3
            jmpSkipClampPos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' mov r8, rcx
            ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)

            patch8 jmpSkipClampPos

            ' Allocate from temp heap
            ff = genAllocTempMemory(OP_TYPE_REG, 8, 7)
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            ' mov r14, rdi (save dest start)
            ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

            genBlockTransfer 6, 7, 8

            ' Update Descriptor
            ff = genUpdateStringDescriptor(scratchIdx, 14, 8)
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            exprIs.DataType = TYPE_STRING
            exprIs.IsTemp = 1
            parseIntrinsic = 1
            EXIT FUNCTION
          END IF
        END IF
      END IF

    CASE TOK_UCASE
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "UCASE$ REQUIRES STRING", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ucaseScratchIdx = resolveSymbol("!UCASESCR" + cTrNum$(t.TempCounter) + "$")
          t.TempCounter = t.TempCounter + 1
          IF ucaseScratchIdx = -1 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ff = genLoadStringDesc(0, 12, 13)

          ' Allocate from temp heap
          ff = genAllocTempMemory(OP_TYPE_REG, 13, 7)
          IF ff = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ' mov r14, rdi (save dest start)
          ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

          ' mov rsi, r12
          ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)
          ' mov rcx, r13
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)

          ' test rcx, rcx
          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          jmpDoneOffset = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ucaseLoopStart = emitPos
          ' lodsb
          opString STR_LODS, REP_NONE, 8

          ' cmp al, 97
          ff = opALU(ALU_CMP, OP_TYPE_ACC, 0, OP_TYPE_IMM, 97, 8)

          ' jl store
          jmpStore1Pos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' cmp al, 122
          ff = opALU(ALU_CMP, OP_TYPE_ACC, 0, OP_TYPE_IMM, 122, 8)

          ' jg store
          jmpStore2Pos = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' sub al, 32
          ff = opALU(ALU_SUB, OP_TYPE_ACC, 0, OP_TYPE_IMM, 32, 8)

          ' store:
          patch8 jmpStore1Pos
          patch8 jmpStore2Pos

          ' stosb
          opString STR_STOS, REP_NONE, 8
          ' dec rcx
          opDecReg 1, 64
          ' jne ucaseLoopStart
          ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, ucaseLoopStart, JCC_TYPE_SHORT)

          ' done:
          patch8 jmpDoneOffset

          ' Update Descriptor
          ff = genUpdateStringDescriptor(ucaseScratchIdx, 14, 13)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          exprIs.DataType = TYPE_STRING
          exprIs.IsTemp = 1
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_ASC
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "ASC REQUIRES STRING", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ff = genLoadStringDesc(0, 6, 1)

          ' xor rax, rax (Clear RAX to return 0 for empty strings)
          ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG_ALT, 0, 64)

          ' test rcx, rcx
          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)

          ' jle .skip_lodsb
          jmpSkipLodsbPos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' lodsb
          opString STR_LODS, REP_NONE, 8

          ' .skip_lodsb:
          patch8 jmpSkipLodsbPos

          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 0
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_CHR
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          ff = genForceNumericIntEx(startIdx + 2, endIdx - 1, allowImplicit, "CHR$ REQUIRES NUMERIC")
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          chrScratchIdx = resolveSymbol("!CHRSCR" + cTrNum$(t.TempCounter) + "$")
          t.TempCounter = t.TempCounter + 1
          IF chrScratchIdx = -1 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ' Allocate from temp heap
          ff = genAllocTempMemory(OP_TYPE_IMM, 1, 7)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          ' mov [rdi], al
          ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 0, 8)

          ' mov r14, rdi
          ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

          ' Update descriptor
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)
          ff = genUpdateStringDescriptor(chrScratchIdx, 14, 1)
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          exprIs.DataType = TYPE_STRING
          exprIs.IsTemp = 1
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_LEN
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN

          innerStart = startIdx + 2
          innerEnd = endIdx - 1

          isVariableLen = 0
          reqSize = -1

          firstTok$ = lineTokens$(innerStart)
          tValFirst = retTokenVal(firstTok$)

          IF tValFirst = 0 THEN
            firstChar$ = LEFT$(firstTok$, 1)
            IF (firstChar$ >= "A" AND firstChar$ <= "Z") OR (firstChar$ >= "a" AND firstChar$ <= "z") OR firstChar$ = "_" THEN
              vName$ = UCASE$(firstTok$)
              vIdx = findSymbol(vName$)
              IF vIdx <> -1 THEN
                isMatch = 0
                isArrayWhole = 0

                IF innerStart = innerEnd THEN
                  isMatch = 1
                ELSE
                  IF innerStart + 2 = innerEnd THEN
                    IF retTokenVal(lineTokens$(innerStart + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(innerEnd)) = 256 + ASC(")") THEN
                      isMatch = 1
                      isArrayWhole = 1
                    END IF
                  ELSE
                    IF retTokenVal(lineTokens$(innerStart + 1)) = 256 + ASC("(") THEN
                      IF findMatchingParen(innerStart + 1, innerEnd) = innerEnd THEN
                        isMatch = 1
                      END IF
                    END IF
                  END IF
                END IF

                IF isMatch = 1 THEN
                  dt = symbols(vIdx).DataType
                  elemSize = 0

                  SELECT CASE dt

                    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
                    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
                    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
                    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
                    CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
                    CASE TYPE_STRING:
                      lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
                      IF floatVarData(lenIdx) > 0 THEN
                        elemSize = floatVarData(lenIdx)
                      ELSE
                        elemSize = -1
                      END IF

                  END SELECT ' dt

                  IF isArrayWhole = 1 THEN
                    IF symbols(vIdx).IsArray = 0 THEN
                      throwCompilerError "EXPECTED ARRAY", ASIS, 0
                      parseIntrinsic = 0
                      EXIT FUNCTION
                    END IF
                    IF elemSize = -1 THEN
                      throwCompilerError "CANNOT USE LEN ON DYNAMIC STRING ARRAY", ASIS, 0
                      parseIntrinsic = 0
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

          IF isVariableLen = 1 THEN
            ff = opMov(OP_TYPE_REG, 0, OP_TYPE_IMM, reqSize, 64)
            exprIs.DataType = TYPE_LONG
            exprIs.IsTemp = 0
            parseIntrinsic = 1
            EXIT FUNCTION
          END IF

          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          exprRes = parseExpression(innerStart, innerEnd, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "VARIABLE REQUIRED FOR NUMERIC LEN", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          ' RAX holds descriptor. load length directly
          ' mov rax, [rax + 8]
          ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), 64)

          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 0
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_INT
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType = TYPE_STRING THEN
            throwCompilerError "INT REQUIRES NUMERIC", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
            opMode = MODE_SSE_DOUBLE
            IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE

            ' movsd xmm1, xmm0
            ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 0, opMode)

            ' cvttsd2si rax, xmm0
            ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)

            ' cvtsi2sd xmm2, rax
            ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 2, OP_TYPE_REG, 0, opMode)

            ' ucomisd xmm1, xmm2 (Sets CF=1 if original fraction was negative and mathematically below truncation)
            ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 1, OP_TYPE_REG, 2, opMode)

            ' jae .skip_dec (If Above or Equal, skip decrement)
            jmpSkipDecPos = opJcc(JCC_JAE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' dec rax
            opDecReg 0, 64

            ' .skip_dec:
            patch8 jmpSkipDecPos
          END IF

          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 0
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF

    CASE TOK_ATN
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          exprRes = parseExpression(startIdx + 2, endIdx - 1, allowImplicit)
          IF exprRes = 0 THEN
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType = TYPE_STRING THEN
            throwCompilerError "ATN REQUIRES NUMERIC", ASIS, 0
            parseIntrinsic = 0
            EXIT FUNCTION
          END IF

          IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
            ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          ELSE
            IF exprIs.DataType = TYPE_SINGLE THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
            END IF
          END IF

          opPushReg 13
          ff = genAlignedCall(IAT_ATAN, 13, DEFAULT)
          opPopReg 13

          exprIs.DataType = TYPE_DOUBLE
          exprIs.IsTemp = 0
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF
      throwCompilerError "MALFORMED ATN", ASIS, 0
      parseIntrinsic = 0
      EXIT FUNCTION

    CASE TOK_LEFT
      IF startIdx + 5 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          comma1 = findNextTokenAtDepth0(startIdx + 2, endIdx - 1, 256 + ASC(","))

          IF comma1 <> -1 THEN
            IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
            expr1Res = parseExpression(startIdx + 2, comma1 - 1, allowImplicit)
            IF expr1Res = 0 THEN parseIntrinsic = 0: EXIT FUNCTION
            IF exprIs.DataType <> TYPE_STRING THEN
              throwCompilerError "LEFT$ ARG 1 MUST BE STRING", ASIS, 0
              parseIntrinsic = 0: EXIT FUNCTION
            END IF
            opPushReg 0

            IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
            ff = genForceNumericIntEx(comma1 + 1, endIdx - 1, allowImplicit, "LEFT$ ARG 2 MUST BE NUMERIC")
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            DIM leftScratchIdx AS INTEGER
            leftScratchIdx = resolveSymbol("!LEFTSCR" + cTrNum$(t.TempCounter) + "$")
            t.TempCounter = t.TempCounter + 1
            IF leftScratchIdx = -1 THEN parseIntrinsic = 0: EXIT FUNCTION

            ' pop r8 (requested length)
            opPopReg 8
            ' pop rax (string descriptor ptr)
            opPopReg 0

            ff = genLoadStringDesc(0, 6, 1)

            ' clamp length to available string length
            ' cmp r8, rcx
            ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)

            ' jle +3
            jmpSkipClamp1Pos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' mov r8, rcx
            ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)

            patch8 jmpSkipClamp1Pos

            ' clamp length to zero minimum
            ' test r8, r8
            ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)

            ' jge +3
            jmpSkipClamp2Pos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' xor r8, r8
            ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)

            patch8 jmpSkipClamp2Pos

            ' Allocate from temp heap
            ff = genAllocTempMemory(OP_TYPE_REG, 8, 7)
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            ' mov r14, rdi (save dest start)
            ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

            genBlockTransfer 6, 7, 8

            ' Update Descriptor
            ff = genUpdateStringDescriptor(leftScratchIdx, 14, 8)
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            exprIs.DataType = TYPE_STRING
            exprIs.IsTemp = 1
            parseIntrinsic = 1
            EXIT FUNCTION
          END IF
        END IF
      END IF
      throwCompilerError "MALFORMED LEFT$", ASIS, 0
      parseIntrinsic = 0
      EXIT FUNCTION

    CASE TOK_RIGHT
      IF startIdx + 5 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          comma1 = findNextTokenAtDepth0(startIdx + 2, endIdx - 1, 256 + ASC(","))

          IF comma1 <> -1 THEN
            IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
            expr1Res = parseExpression(startIdx + 2, comma1 - 1, allowImplicit)
            IF expr1Res = 0 THEN parseIntrinsic = 0: EXIT FUNCTION
            IF exprIs.DataType <> TYPE_STRING THEN
              throwCompilerError "RIGHT$ ARG 1 MUST BE STRING", ASIS, 0
              parseIntrinsic = 0: EXIT FUNCTION
            END IF
            opPushReg 0

            IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
            ff = genForceNumericIntEx(comma1 + 1, endIdx - 1, allowImplicit, "RIGHT$ ARG 2 MUST BE NUMERIC")
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            DIM rightScratchIdx AS INTEGER
            rightScratchIdx = resolveSymbol("!RIGHTSCR" + cTrNum$(t.TempCounter) + "$")
            t.TempCounter = t.TempCounter + 1
            IF rightScratchIdx = -1 THEN parseIntrinsic = 0: EXIT FUNCTION

            ' pop r8 (requested length)
            opPopReg 8
            ' pop rax (string descriptor ptr)
            opPopReg 0

            ff = genLoadStringDesc(0, 6, 1)

            ' clamp length to available string length
            ' cmp r8, rcx
            ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)

            ' jle +3
            jmpSkipClamp1Pos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' mov r8, rcx
            ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)

            patch8 jmpSkipClamp1Pos

            ' clamp length to zero minimum
            ' test r8, r8
            ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)

            ' jge +3
            jmpSkipClamp2Pos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

            ' xor r8, r8
            ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)

            patch8 jmpSkipClamp2Pos

            ' Adjust RSI to start at (Length - RequestedLength)
            ' mov rdx, rcx
            ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 1, 64)
            ' sub rdx, r8
            ff = opALU(ALU_SUB, OP_TYPE_REG, 2, OP_TYPE_REG, 8, 64)
            ' add rsi, rdx
            ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_REG, 2, 64)

            ' Allocate from temp heap
            ff = genAllocTempMemory(OP_TYPE_REG, 8, 7)
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            ' mov r14, rdi (save dest start)
            ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

            genBlockTransfer 6, 7, 8

            ' Update Descriptor
            ff = genUpdateStringDescriptor(rightScratchIdx, 14, 8)
            IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

            exprIs.DataType = TYPE_STRING
            exprIs.IsTemp = 1
            parseIntrinsic = 1
            EXIT FUNCTION
          END IF
        END IF
      END IF
      throwCompilerError "MALFORMED RIGHT$", ASIS, 0
      parseIntrinsic = 0
      EXIT FUNCTION

    CASE TOK_KEYDOWN
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          ff = genForceNumericIntEx(startIdx + 2, endIdx - 1, allowImplicit, "_KEYDOWN REQUIRES NUMERIC")
          IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

          ' Call RT_KEYDOWN runtime helper
          addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_KEYDOWN, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseIntrinsic = 0: EXIT FUNCTION

          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 0
          parseIntrinsic = 1
          EXIT FUNCTION
        END IF
      END IF
      throwCompilerError "MALFORMED _KEYDOWN", ASIS, 0
      parseIntrinsic = 0
      EXIT FUNCTION

    CASE TOK_INKEY
      IF compileHasGraphics = 0 THEN
        DIM inkeyScratchIdx AS INTEGER
        inkeyScratchIdx = resolveSymbol("!INKEYSCR" + cTrNum$(t.TempCounter) + "$")
        t.TempCounter = t.TempCounter + 1
        IF inkeyScratchIdx = -1 THEN
          parseIntrinsic = 0
          EXIT FUNCTION
        END IF

        ' Allocate 1 byte from Temp Heap unconditionally
        ff = genAllocTempMemory(OP_TYPE_IMM, 1, 7)
        IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

        ' Save data start ptr
        ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

        ' mov r15, 8
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)

        inkeyLoopStart = emitPos

        ' mov rcx, r15
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)

        ff = genAlignedCall(IAT_GETASYNCKEYSTATE, 13, DEFAULT)

        ' test ax, &H8000
        ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)

        ' jz .next
        jmpNextPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

        ' Quick mapping for Numpad keys (96-105 to 48-57)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 96, 8)
        jmpSkipNumpadA1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 105, 8)
        jmpSkipNumpadA2 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opALU(ALU_SUB, OP_TYPE_REG, 15, OP_TYPE_IMM, 48, 8)
        patch8 jmpSkipNumpadA1
        patch8 jmpSkipNumpadA2

        ' Quick mapping for arrow keys (Translates VK codes 37-40 to character values 52, 56, 54, 50)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 37, 8)
        jmpNotLeft = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 52, 8)
        jmpMapDone1 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotLeft

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 38, 8)
        jmpNotUp = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 56, 8)
        jmpMapDone2 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotUp

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 39, 8)
        jmpNotRight = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 54, 8)
        jmpMapDone3 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotRight

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 40, 8)
        jmpNotDown = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 50, 8)
        jmpMapDone4 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotDown

        patch8 jmpMapDone1
        patch8 jmpMapDone2
        patch8 jmpMapDone3
        patch8 jmpMapDone4

        ' mov [r14], r15b
        ff = opMov(OP_TYPE_MEM_REG, 14, OP_TYPE_REG, 15, 8)
        ' mov rcx, 1
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)

        ' jmp .done
        jmpDonePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

        ' .next:
        patch8 jmpNextPos

        ' inc r15
        opIncReg 15, 64

        ' cmp r15, 255
        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)

        ' jl .loop
        ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, inkeyLoopStart, JCC_TYPE_NEAR)

        ' Empty return
        ' mov rcx, 0
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 0, 64)

        ' .done:
        patch8 jmpDonePos

        ' Update Descriptor
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
        ff = genUpdateStringDescriptor(inkeyScratchIdx, 14, 1)
        IF ff = 0 THEN parseIntrinsic = 0: EXIT FUNCTION

        exprIs.DataType = TYPE_STRING
        exprIs.IsTemp = 1
        parseIntrinsic = 1
        EXIT FUNCTION
      END IF

    CASE ELSE
      throwCompilerError "UNIMPLEMENTED INTRINSIC OR TOKEN", ASIS, 0
      parseIntrinsic = 0
      EXIT FUNCTION

  END SELECT ' tVal

  parseIntrinsic = tempSuccess

END FUNCTION ' parseIntrinsic

''''''''''''''''''''''''
FUNCTION parseRoutineCall (startIdx, isExplicit)

  DIM targetType AS LONG
  DIM opMode AS LONG
  DIM rhsTokIdx AS LONG
  DIM rhsName$
  DIM rhsIdx AS LONG
  DIM rhsHasIndex AS LONG
  DIM rhsParenStart AS LONG
  DIM rhsCloseParenIdx AS LONG
  DIM rhsCommaIdx AS LONG
  DIM rhsAxIdx AS LONG
  DIM rhsHasField AS LONG
  DIM rhsUdtOffset AS LONG
  DIM rhsUdtIndex AS LONG
  DIM rhsFieldName$
  DIM rUIdx AS LONG
  DIM rFFound AS LONG
  DIM lhsUdtIndex AS LONG
  DIM fieldCnt AS LONG
  DIM fieldOffset AS LONG
  DIM fieldSize AS LONG
  DIM fType AS LONG
  DIM f AS LONG
  DIM elemSize AS LONG
  DIM jmpSkipRhsNullArg AS LONG
  DIM jmpHasDescArg AS LONG
  DIM emptyDescIdx AS LONG

  tempSuccess = 0

  IF isExplicit = 1 THEN
    IF lineTokenCount < startIdx + 2 THEN
      throwCompilerError "EXPECTED SUB NAME", ASIS, 0
      parseRoutineCall = 0
      EXIT FUNCTION
    END IF
    subName$ = UCASE$(lineTokens$(startIdx + 1))
    argStartIdx = startIdx + 2
  ELSE
    subName$ = UCASE$(lineTokens$(startIdx))
    argStartIdx = startIdx + 1
  END IF

  vIdx = resolveSymbol(subName$)
  IF vIdx = -1 THEN
    parseRoutineCall = 0
    EXIT FUNCTION
  END IF

  subIdx = symbols(vIdx).SubIndex
  IF subIdx = -1 THEN
    throwCompilerError "SUB NOT FOUND", ASIS, 0
    parseRoutineCall = 0
    EXIT FUNCTION
  END IF

  endStmtIdx = findInstructionEnd(argStartIdx)
  nextStmtIdx = returnedData2

  tokIdx = argStartIdx
  argIdx = 0

  hasParens = 0
  IF tokIdx <= endStmtIdx THEN
    IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
      IF findMatchingParen(tokIdx, endStmtIdx) = endStmtIdx THEN
        hasParens = 1
        tokIdx = tokIdx + 1
        endStmtIdx = endStmtIdx - 1
      END IF
    END IF
  END IF

  DO WHILE tokIdx <= endStmtIdx
    exprEndIdx = findNextTokenAtDepth0(tokIdx, endStmtIdx, 256 + ASC(","))
    IF exprEndIdx = -1 THEN
      exprEndIdx = endStmtIdx + 1
    END IF

    IF tokIdx > exprEndIdx - 1 THEN
      throwCompilerError "MISSING ARGUMENT", ASIS, 0
      parseRoutineCall = 0
      EXIT FUNCTION
    END IF

    IF argIdx >= subs(subIdx).ArgCount THEN
      throwCompilerError "TOO MANY ARGS FOR " + subName$, ASIS, 0
      parseRoutineCall = 0
      EXIT FUNCTION
    END IF

    targetVarIdx = subArgVarIdx(subIdx, argIdx)
    targetType = symbols(targetVarIdx).DataType

    IF targetType = TYPE_UDT THEN
      rhsTokIdx = tokIdx
      rhsName$ = UCASE$(lineTokens$(rhsTokIdx))
      rhsIdx = resolveSymbol(rhsName$)
      IF rhsIdx = -1 THEN parseRoutineCall = 0: EXIT FUNCTION

      rhsTokIdx = rhsTokIdx + 1

      rhsHasIndex = 0
      rhsParenStart = 0
      rhsCloseParenIdx = -1
      rhsCommaIdx = -1

      IF rhsTokIdx <= exprEndIdx - 1 THEN
        IF retTokenVal(lineTokens$(rhsTokIdx)) = 256 + ASC("(") THEN
          rhsHasIndex = 1
          rhsParenStart = rhsTokIdx
          rhsCloseParenIdx = findMatchingParen(rhsTokIdx, exprEndIdx - 1)
          IF rhsCloseParenIdx = -1 THEN
            throwCompilerError "MISSING )", ASIS, 0
            parseRoutineCall = 0: EXIT FUNCTION
          END IF
          rhsCommaIdx = findNextTokenAtDepth0(rhsTokIdx + 1, rhsCloseParenIdx - 1, 256 + ASC(","))
          rhsTokIdx = rhsCloseParenIdx + 1
        END IF
      END IF

      rhsHasField = 0
      rhsUdtOffset = 0
      rhsUdtIndex = -1

      IF symbols(rhsIdx).DataType = TYPE_UDT THEN
        rhsUdtIndex = symbols(rhsIdx).UDTIndex
      END IF

      IF rhsTokIdx <= exprEndIdx - 1 THEN
        IF retTokenVal(lineTokens$(rhsTokIdx)) = 256 + ASC(".") THEN
          rhsHasField = 1
          rhsTokIdx = rhsTokIdx + 1
          IF rhsTokIdx > exprEndIdx - 1 THEN
            throwCompilerError "EXPECTED FIELD NAME", ASIS, 0
            parseRoutineCall = 0: EXIT FUNCTION
          END IF

          rhsFieldName$ = UCASE$(lineTokens$(rhsTokIdx))
          rhsTokIdx = rhsTokIdx + 1

          IF symbols(rhsIdx).DataType <> TYPE_UDT THEN
            throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
            parseRoutineCall = 0: EXIT FUNCTION
          END IF

          rUIdx = symbols(rhsIdx).UDTIndex
          rFFound = 0
          FOR f = 0 TO udts(rUIdx).FieldCount - 1
            IF RTRIM$(udtFields(rUIdx, f).FieldName) = rhsFieldName$ THEN
              rhsUdtOffset = udtFields(rUIdx, f).Offset
              IF udtFields(rUIdx, f).DataType <> TYPE_UDT THEN
                throwCompilerError "TYPE MISMATCH", ASIS, 0
                parseRoutineCall = 0: EXIT FUNCTION
              END IF
              rhsUdtIndex = udtFields(rUIdx, f).UDTIndex
              rFFound = 1
              EXIT FOR
            END IF
          NEXT

          IF rFFound = 0 THEN
            throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
            parseRoutineCall = 0: EXIT FUNCTION
          END IF
        END IF
      END IF

      IF rhsUdtIndex = -1 THEN
        throwCompilerError "RHS IS NOT A UDT", ASIS, 0
        parseRoutineCall = 0: EXIT FUNCTION
      END IF

      lhsUdtIndex = symbols(targetVarIdx).UDTIndex

      IF rhsUdtIndex <> lhsUdtIndex THEN
        throwCompilerError "UDT TYPE MISMATCH", ASIS, 0
        parseRoutineCall = 0: EXIT FUNCTION
      END IF

      IF rhsHasIndex = 1 THEN
        IF symbols(rhsIdx).IsArray = 0 THEN
          throwCompilerError "ARRAY NOT DIMMED", ASIS, 0
          parseRoutineCall = 0: EXIT FUNCTION
        END IF

        IF rhsCommaIdx = -1 THEN
          ff = genForceNumericIntEx(rhsParenStart + 1, rhsCloseParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
          IF ff = 0 THEN parseRoutineCall = 0: EXIT FUNCTION
          opPushReg 0 ' Push X
        ELSE
          ff = genForceNumericIntEx(rhsParenStart + 1, rhsCommaIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
          IF ff = 0 THEN parseRoutineCall = 0: EXIT FUNCTION
          opPushReg 0 ' Push X

          ff = genForceNumericIntEx(rhsCommaIdx + 1, rhsCloseParenIdx - 1, 0, "ARRAY INDEX MUST BE NUMERIC")
          IF ff = 0 THEN parseRoutineCall = 0: EXIT FUNCTION
          opPushReg 0 ' Push Y
        END IF
      END IF

      ' Calculate RHS Address into R9
      IF symbols(rhsIdx).IsArray = 2 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 9, OP_TYPE_MEM_RIP, 0, 64, rhsIdx)
      ELSE
        ff = genSymbolRouteLea(9, rhsIdx)
      END IF

      IF rhsHasIndex = 1 THEN
        IF rhsCommaIdx <> -1 THEN
          opPopReg 3 ' Y
          opPopReg 0 ' X
          rhsAxIdx = resolveSymbol("!" + RTRIM$(symbols(rhsIdx).RecordName) + "_AX")
          ff = genSymbolRouteMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64, rhsAxIdx)
          ff = opImul(3, OP_TYPE_REG, 8, 0, MODE_IMUL64_REG)
          ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
        ELSE
          opPopReg 0 ' X
        END IF

        elemSize = udts(symbols(rhsIdx).UDTIndex).TotalSize
        IF elemSize <> 1 THEN
          ff = opImul(0, OP_TYPE_REG, 0, elemSize, MODE_IMUL64_IMM32)
        END IF

        ff = opALU(ALU_ADD, OP_TYPE_REG, 9, OP_TYPE_REG, 0, 64)
      END IF

      IF rhsUdtOffset > 0 THEN
        ff = opALU(ALU_ADD, OP_TYPE_REG, 9, OP_TYPE_IMM, rhsUdtOffset, 64)
      END IF

      opPushReg 9 ' Save RHS Address to stack securely

      ' Calculate LHS address into R8 (Argument Variable)
      IF symbols(targetVarIdx).IsArray = 2 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 8, OP_TYPE_MEM_RIP, 0, 64, targetVarIdx)
      ELSE
        ff = genSymbolRouteLea(8, targetVarIdx)
      END IF

      opPopReg 9 ' Restore RHS Address from stack into R9

      ' Process UDT fields for structural deep copy into Argument parameter slot
      fieldCnt = udts(lhsUdtIndex).FieldCount

      FOR f = 0 TO fieldCnt - 1
        fieldOffset = udtFields(lhsUdtIndex, f).Offset
        fieldSize = udtFields(lhsUdtIndex, f).Size
        fType = udtFields(lhsUdtIndex, f).DataType

        IF fType = TYPE_STRING AND udtFields(lhsUdtIndex, f).UDTIndex = 1 THEN
          ' Get RHS Desc Ptr
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 9, 64)
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, fieldOffset, 64)
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG, 2, 64) ' RDX = [RHS + offset]

          ' If RDX is NULL, point it to !EMPTY_DESC$
          ff = opTest(OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)
          jmpSkipRhsNullArg = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
          emptyDescIdx = resolveSymbol("!EMPTY_DESC$")
          ff = genSymbolRouteMov(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64, emptyDescIdx)
          patch8 jmpSkipRhsNullArg

          ' Get LHS Desc Ptr (and allocate if NULL)
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 8, 64)
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 1, OP_TYPE_IMM, fieldOffset, 64)

          ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG, 1, 64) ' R10 = actual pointer
          ff = opTest(OP_TYPE_REG, 10, OP_TYPE_REG, 10, 64)
          jmpHasDescArg = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

          ' Allocate 24 bytes
          opPushReg 1
          opPushReg 2
          opPushReg 8
          opPushReg 9

          ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, PROCESS_HEAP_VAR_IDX)
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_IMM, 8, 32)
          ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 24, 32)
          ff = genAlignedCall(IAT_HEAPALLOC, 13, DEFAULT)
          ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 0, 64) ' R10 = new alloc

          opPopReg 9
          opPopReg 8
          opPopReg 2
          opPopReg 1

          ' Store new desc pointer into LHS field
          ff = opMov(OP_TYPE_MEM_REG, 1, OP_TYPE_REG, 10, 64)

          patch8 jmpHasDescArg

          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 10, 64) ' RCX = LHS Desc Ptr

          opPushReg 8
          opPushReg 9
          addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION
          opPopReg 9
          opPopReg 8
        ELSE
          ' Raw block transfer (Fixed strings, numbers, embedded static sub-structs)
          ff = opMov(OP_TYPE_REG, 7, OP_TYPE_REG, 8, 64) ' RDI
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 7, OP_TYPE_IMM, fieldOffset, 64)

          ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 9, 64) ' RSI
          IF fieldOffset > 0 THEN ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_IMM, fieldOffset, 64)

          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, fieldSize, 64) ' RCX

          opPushReg 8
          opPushReg 9

          opFlag FLAG_CLD
          opString STR_MOVS, REP_REP, 8

          opPopReg 9
          opPopReg 8
        END IF
      NEXT f

    ELSE
      ' Standard scalar argument processing
      exprRes = parseExpression(tokIdx, exprEndIdx - 1, 1)
      IF exprRes = 0 THEN
        parseRoutineCall = 0
        EXIT FUNCTION
      END IF

      IF symbols(targetVarIdx).IsArray = 2 THEN
        IF exprIs.DataType = TYPE_STRING AND symbols(targetVarIdx).DataType <> TYPE_STRING THEN
          throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
          parseRoutineCall = 0
          EXIT FUNCTION
        END IF
        IF exprIs.DataType <> TYPE_STRING AND symbols(targetVarIdx).DataType = TYPE_STRING THEN
          throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
          parseRoutineCall = 0
          EXIT FUNCTION
        END IF

        ' Extract pointer from RAX
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, targetVarIdx)
        IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION

        ' Copy _AX and _AY stride metadata for 2D arrays
        srcArgName$ = UCASE$(lineTokens$(tokIdx))
        srcArgIdx = resolveSymbol(srcArgName$)
        IF srcArgIdx <> -1 THEN
          srcBase$ = RTRIM$(symbols(srcArgIdx).RecordName)
          tgtBase$ = RTRIM$(symbols(targetVarIdx).RecordName)

          srcAxIdx = resolveSymbol("!" + srcBase$ + "_AX")
          srcAyIdx = resolveSymbol("!" + srcBase$ + "_AY")
          tgtAxIdx = resolveSymbol("!" + tgtBase$ + "_AX")
          tgtAyIdx = resolveSymbol("!" + tgtBase$ + "_AY")

          ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, srcAxIdx)
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, tgtAxIdx)

          ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, srcAyIdx)
          ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, tgtAyIdx)
        END IF

      ELSE
        IF exprIs.DataType = TYPE_STRING THEN
          IF symbols(targetVarIdx).DataType <> TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
            parseRoutineCall = 0
            EXIT FUNCTION
          END IF

          ' Extract descriptor pointer from RAX directly into RDX (2)
          ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 0, 64)

          ' Load LHS Descriptor Address into RCX
          ff = genSymbolRouteMov(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64, targetVarIdx)
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION

          ' Call RT_STR_ASSIGN runtime helper
          addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_STR_ASSIGN, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION
        ELSE
          IF symbols(targetVarIdx).DataType = TYPE_STRING THEN
            throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
            parseRoutineCall = 0
            EXIT FUNCTION
          END IF

          targetType = symbols(targetVarIdx).DataType
          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
              ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
              exprIs.DataType = TYPE_DOUBLE
            END IF
            IF exprIs.DataType = TYPE_DOUBLE AND targetType = TYPE_SINGLE THEN
              ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
            END IF
            IF exprIs.DataType = TYPE_SINGLE AND targetType = TYPE_DOUBLE THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
            END IF
            opMode = MODE_SSE_DOUBLE
            IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
            ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, opMode, targetVarIdx)
          ELSE
            IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
              opMode = MODE_SSE_DOUBLE
              IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF

            SELECT CASE targetType

              CASE TYPE_BYTE, TYPE_UBYTE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 8, targetVarIdx)
              CASE TYPE_INTEGER, TYPE_UINTEGER
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 16, targetVarIdx)
              CASE TYPE_LONG, TYPE_ULONG
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, targetVarIdx)
              CASE ELSE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, targetVarIdx)

            END SELECT ' targetType

          END IF
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION
        END IF
      END IF
    END IF

    argIdx = argIdx + 1
    tokIdx = exprEndIdx + 1 ' Skip comma
  LOOP

  IF argIdx < subs(subIdx).ArgCount THEN
    throwCompilerError "TOO FEW ARGS FOR " + subName$, ASIS, 0
    parseRoutineCall = 0
    EXIT FUNCTION
  END IF

  ' Emit CALL
  addPatchStr PATCH_CALL, opCall(0, CALLMODE_REL32), subName$
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION

  IF subs(subIdx).IsFunction = 1 THEN
    retVarIdx = subs(subIdx).ReturnVarIdx
    exprIs.DataType = symbols(retVarIdx).DataType
    exprIs.IsTemp = 0

    SELECT CASE symbols(retVarIdx).DataType

      CASE TYPE_SINGLE
        ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_SINGLE, retVarIdx)

      CASE TYPE_DOUBLE
        ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, MODE_SSE_DOUBLE, retVarIdx)

      CASE ELSE
        ff = genSymbolRouteMov(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64, retVarIdx)

    END SELECT ' DataType

    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN parseRoutineCall = 0: EXIT FUNCTION
  ELSE
    ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
    exprIs.DataType = TYPE_LONG
    exprIs.IsTemp = 0
  END IF

  IF nextStmtIdx <> -1 THEN
    tempSuccess = parseStatement(nextStmtIdx)
  ELSE
    tempSuccess = 1
  END IF

  parseRoutineCall = tempSuccess

END FUNCTION ' parseRoutineCall

''''''''''''''''''''''''
FUNCTION parseStatement (startIdx)

  ' Clear any lingering context hints from previous expression evaluations to prevent duck-typing leaks
  expectedSymType = TYPE_ANY

  tempSuccess = 1
  firstTok$ = lineTokens$(startIdx)
  tVal = retTokenVal(firstTok$)

  SELECT CASE tVal

    CASE TOK_CLASSIC ' Used with #
      parseStatement = 1
      EXIT FUNCTION

    CASE TOK_DEFINT ' Used with #
      ' Handled entirely in compilePass2Scan. We bypass this in the emission pass.
      endStmtIdx = findInstructionEnd(startIdx + 1)
      nextStmtIdx = returnedData2

      IF nextStmtIdx <> -1 THEN
        parseStatement = parseStatement(nextStmtIdx)
      ELSE
        parseStatement = 1
      END IF
      EXIT FUNCTION

    CASE TOK_GDOUBLE
      parseStatement = 1
      EXIT FUNCTION

    CASE TOK_GRAPHICS
      tokIdx = startIdx + 1

      IF tokIdx < lineTokenCount THEN
        gTok$ = lineTokens$(tokIdx)
        IF LEFT$(gTok$, 1) >= "0" AND LEFT$(gTok$, 1) <= "9" THEN
          gfxConfig.SizeX = VAL(gTok$)
          IF gfxConfig.SizeX < 64 OR gfxConfig.SizeX > FRAMEBUF_MAX_WIDTH THEN
            throwCompilerError "X MUST BE 64 TO 1024", ASIS, 0
            parseStatement = 0
            EXIT FUNCTION
          END IF
          tokIdx = tokIdx + 1

          IF tokIdx < lineTokenCount THEN
            IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
              tokIdx = tokIdx + 1
            ELSE
              throwCompilerError "EXPECTED COMMA AFTER X", ASIS, 0
              parseStatement = 0
              EXIT FUNCTION
            END IF
          ELSE
            throwCompilerError "EXPECTED Y RESOLUTION", ASIS, 0
            parseStatement = 0
            EXIT FUNCTION
          END IF

          IF tokIdx < lineTokenCount THEN
            gTok$ = lineTokens$(tokIdx)
            IF LEFT$(gTok$, 1) >= "0" AND LEFT$(gTok$, 1) <= "9" THEN
              gfxConfig.SizeY = VAL(gTok$)
              IF gfxConfig.SizeY < 64 OR gfxConfig.SizeY > FRAMEBUF_MAX_HEIGHT THEN
                throwCompilerError "Y MUST BE 64 TO 1080", ASIS, 0
                parseStatement = 0
                EXIT FUNCTION
              END IF
              tokIdx = tokIdx + 1
            ELSE
              throwCompilerError "EXPECTED Y RESOLUTION", ASIS, 0
              parseStatement = 0
              EXIT FUNCTION
            END IF
          ELSE
            throwCompilerError "EXPECTED Y RESOLUTION", ASIS, 0
            parseStatement = 0
            EXIT FUNCTION
          END IF

          IF tokIdx < lineTokenCount THEN
            IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(",") THEN
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
          parseStatement = 0
          EXIT FUNCTION
        END IF
      END IF

      IF tokIdx < lineTokenCount THEN
        throwCompilerError "UNEXPECTED TOKEN IN GRAPHICS", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      parseStatement = 1
      EXIT FUNCTION

    CASE TOK_BEEP
      beepRes = parse_BEEP(startIdx)
      IF beepRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "BEEP FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_CALL
      callRes = parseRoutineCall(startIdx, 1)
      IF callRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CALL FAILED", ASIS, 0
      ELSE
        tempSuccess = callRes
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_CASE
      caseRes = parse_CASE(startIdx)
      IF caseRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CASE FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_CLS
      clsRes = parse_CLS(startIdx)
      IF clsRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "CLS FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_COLOR
      colorRes = parse_COLOR(startIdx)
      IF colorRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "COLOR FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_COMMON
      commonRes = parse_COMMON(startIdx)
      IF commonRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "COMMON FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_DEF
      endStmtIdx = findInstructionEnd(startIdx + 1)
      nextStmtIdx = returnedData2

      IF endStmtIdx >= startIdx + 1 THEN
        IF UCASE$(lineTokens$(startIdx + 1)) = "SEG" THEN
          IF nextStmtIdx <> -1 THEN
            parseStatement = parseStatement(nextStmtIdx)
          ELSE
            parseStatement = 1
          END IF
          EXIT FUNCTION
        END IF
      END IF

      IF endStmtIdx < startIdx + 2 THEN
        throwCompilerError "MALFORMED DEF", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      defNameTok$ = lineTokens$(startIdx + 1)
      isDefFnSpace = 0
      IF UCASE$(defNameTok$) = "FN" THEN isDefFnSpace = 1

      IF isDefFnSpace = 0 AND LEFT$(defNameTok$, 2) <> "Fn" THEN
        throwCompilerError "DEF MUST BE FOLLOWED BY FN OR Fn*()", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      nameIdx = startIdx + 1
      subName$ = UCASE$(defNameTok$)

      IF isDefFnSpace = 1 THEN
        IF endStmtIdx >= startIdx + 2 THEN
          nameIdx = startIdx + 2
          subName$ = "FN" + UCASE$(lineTokens$(startIdx + 2))
        ELSE
          throwCompilerError "MALFORMED DEF", ASIS, 0
          parseStatement = 0
          EXIT FUNCTION
        END IF
      END IF

      subIdx = -1
      FOR ii = 0 TO subCount - 1
        IF RTRIM$(subs(ii).RecordName) = subName$ THEN
          subIdx = ii
          EXIT FOR
        END IF
      NEXT

      IF subIdx = -1 THEN
        throwCompilerError "DEF NOT FOUND", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      currentScopeID = subs(subIdx).ScopeID
      insideSub = 2
      currentSubName$ = subName$

      subs(subIdx).JmpPatchPos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)
      subs(subIdx).Offset = emitPos

      emitSubPrologue

      eqIdx = -1
      FOR ii = nameIdx + 1 TO endStmtIdx
        IF retTokenVal(lineTokens$(ii)) = 256 + ASC("=") THEN
          eqIdx = ii
          EXIT FOR
        END IF
      NEXT

      IF eqIdx = -1 THEN
        throwCompilerError "DEF MISSING =", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      exprRes = parseExpression(eqIdx + 1, endStmtIdx, 0)
      IF exprRes = 0 THEN
        parseStatement = 0
        EXIT FUNCTION
      END IF

      retVarIdx = subs(subIdx).ReturnVarIdx
      targetType = symbols(retVarIdx).DataType

      IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
        IF exprIs.DataType <> TYPE_SINGLE AND exprIs.DataType <> TYPE_DOUBLE THEN
          ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
          exprIs.DataType = TYPE_DOUBLE
        END IF
        IF exprIs.DataType = TYPE_DOUBLE AND targetType = TYPE_SINGLE THEN
          ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
        END IF
        IF exprIs.DataType = TYPE_SINGLE AND targetType = TYPE_DOUBLE THEN
          ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
        END IF
        opMode = MODE_SSE_DOUBLE
        IF targetType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
        ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, opMode, retVarIdx)
      ELSE
        IF exprIs.DataType = TYPE_SINGLE OR exprIs.DataType = TYPE_DOUBLE THEN
          opMode = MODE_SSE_DOUBLE
          IF exprIs.DataType = TYPE_SINGLE THEN opMode = MODE_SSE_SINGLE
          ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
        END IF

        SELECT CASE targetType

          CASE TYPE_BYTE, TYPE_UBYTE
            ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 8, retVarIdx)
          CASE TYPE_INTEGER, TYPE_UINTEGER
            ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 16, retVarIdx)
          CASE TYPE_LONG, TYPE_ULONG
            ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 32, retVarIdx)
          CASE ELSE
            ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, retVarIdx)

        END SELECT ' targetType

      END IF

      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        parseStatement = 0
        EXIT FUNCTION
      END IF

      emitSubEpilogue

      patch32 subs(subIdx).JmpPatchPos, emitPos - (subs(subIdx).JmpPatchPos + 4)

      currentScopeID = 0
      insideSub = 0
      currentSubName$ = ""

      IF nextStmtIdx <> -1 THEN
        parseStatement = parseStatement(nextStmtIdx)
      ELSE
        parseStatement = 1
      END IF
      EXIT FUNCTION

    CASE TOK_DIM
      dimRes = parse_DIM(startIdx)
      IF dimRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "DIM FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_DO
      doRes = parse_DO(startIdx)
      IF doRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "DO FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_ELSE
      endStmtIdx = findInstructionEnd(startIdx + 1)
      nextStmtIdx = returnedData2

      IF ctrlCount = 0 THEN
        throwCompilerError "ELSE WITHOUT IF", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF
      IF ctrls(ctrlCount - 1).Type <> CTRL_IF THEN
        throwCompilerError "ELSE WITHOUT IF", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      jmpEnd = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ' Add jump to the linked list in Patch2 so END IF resolves it
      patch32 jmpEnd, ctrls(ctrlCount - 1).Patch2
      ctrls(ctrlCount - 1).Patch2 = jmpEnd

      ' Resolve the false patch from the previous IF block to land right here
      prevPatch = ctrls(ctrlCount - 1).Patch1
      IF prevPatch <> 0 THEN
        patch32 prevPatch, emitPos - (prevPatch + 4)
      END IF

      ctrls(ctrlCount - 1).Type = CTRL_ELSE
      ctrls(ctrlCount - 1).Patch1 = 0

      IF nextStmtIdx <> -1 THEN
        parseStatement = parseStatement(nextStmtIdx)
      ELSE
        parseStatement = 1
      END IF
      EXIT FUNCTION

    CASE TOK_END
      endRes = parse_END(startIdx)
      IF endRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "END FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_EXIT
      exitRes = parse_EXIT(startIdx)
      IF exitRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "EXIT FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_FOR
      forRes = parse_FOR(startIdx)
      IF forRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "FOR FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_FUNCTION
      IF lineTokenCount < startIdx + 2 THEN
        throwCompilerError "MALFORMED FUNCTION", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      subName$ = UCASE$(lineTokens$(startIdx + 1))
      subIdx = -1
      FOR ii = 0 TO subCount - 1
        IF RTRIM$(subs(ii).RecordName) = subName$ THEN
          subIdx = ii
          EXIT FOR
        END IF
      NEXT

      IF subIdx = -1 THEN
        throwCompilerError "FUNCTION NOT FOUND", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      currentScopeID = subs(subIdx).ScopeID
      insideSub = 2
      currentSubName$ = subName$ ' Emit jump over FUNCTION
      subs(subIdx).JmpPatchPos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      subs(subIdx).Offset = emitPos

      ' Align stack for internal FUNCTION, preserve ABI non-volatiles, and allocate frame
      emitSubPrologue

      parseStatement = 1
      EXIT FUNCTION

    CASE TOK_GLOBAL
      globalRes = parse_GLOBAL(startIdx)
      IF globalRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "GLOBAL FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_GOTO
      gotoRes = parse_GOTO(startIdx)
      IF gotoRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "GOTO FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_IF
      ifRes = parse_IF(startIdx)
      IF ifRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "IF FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_INPUT
      inputRes = parse_INPUT(startIdx)
      IF inputRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "INPUT FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_LET
      assignRes = parseAssign(startIdx + 1)
      IF assignRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "ASSIGN FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_LINE
      IF compileHasGraphics = 0 THEN
        throwCompilerError "LINE REQUIRES #GRAPHICS", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF
      lineRes = parse_LINE(startIdx)
      IF lineRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "LINE FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_LOCATE
      locateRes = parse_LOCATE(startIdx)
      IF locateRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "LOCATE FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_LOOP
      loopRes = parse_LOOP(startIdx)
      IF loopRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "LOOP FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_NEXT
      nextRes = parse_NEXT(startIdx)
      IF nextRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "NEXT FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_ON
      onRes = parse_ON(startIdx)
      IF onRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "ON FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_PRINT
      printRes = parse_PRINT(startIdx)
      IF printRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "PRINT FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_PSET
      IF compileHasGraphics = 0 THEN
        throwCompilerError "PSET REQUIRES #GRAPHICS", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF
      psetRes = parse_PSET(startIdx)
      IF psetRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "PSET FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_RESUME
      resumeRes = parse_RESUME(startIdx)
      IF resumeRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "RESUME FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_RETURN
      returnRes = parse_RETURN(startIdx)
      IF returnRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "RETURN FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_SCREEN, TOK_FULLSCREEN, TOK_FONT, TOK_LIMIT, TOK_DISPLAY
      ' Warnings for these are now emitted earlier in compilePass2Scan
      parseStatement = 1
      EXIT FUNCTION

    CASE TOK_SELECT
      selectRes = parse_SELECT(startIdx)
      IF selectRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        tempSuccess = 0
        IF compileStatusMsg$ = "" THEN throwCompilerError "SELECT FAILED", ASIS, 0
      END IF
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE TOK_STRING
      endStmtIdx = findInstructionEnd(startIdx + 1)
      nextStmtIdx = returnedData2

      IF endStmtIdx < startIdx + 1 THEN
        throwCompilerError "EXPECTED IDENTIFIER", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      vTok$ = lineTokens$(startIdx + 1)
      IF retTokenVal(vTok$) <> 0 THEN
        throwCompilerError "EXPECTED IDENTIFIER", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      vName$ = UCASE$(vTok$)

      vIdx = resolveSymbol(vName$)
      IF vIdx = -1 THEN
        parseStatement = 0
        EXIT FUNCTION
      END IF

      ' Check for assignment
      IF endStmtIdx >= startIdx + 2 THEN
        IF retTokenVal(lineTokens$(startIdx + 2)) = 256 + ASC("=") THEN
          ' It's an assignment, delegate to parseAssign
          assignRes = parseAssign(startIdx + 1)
          IF assignRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
            tempSuccess = 0
            IF compileStatusMsg$ = "" THEN throwCompilerError "ASSIGN FAILED", ASIS, 0
          END IF
          parseStatement = tempSuccess
          EXIT FUNCTION
        ELSE
          throwCompilerError "EXPECTED =", ASIS, 0
          parseStatement = 0
          EXIT FUNCTION
        END IF
      END IF

      IF nextStmtIdx <> -1 THEN
        parseStatement = parseStatement(nextStmtIdx)
      ELSE
        parseStatement = 1
      END IF
      EXIT FUNCTION

    CASE TOK_SUB
      IF lineTokenCount < startIdx + 2 THEN
        throwCompilerError "MALFORMED SUB", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      subName$ = UCASE$(lineTokens$(startIdx + 1))
      subIdx = -1
      FOR ii = 0 TO subCount - 1
        IF RTRIM$(subs(ii).RecordName) = subName$ THEN
          subIdx = ii
          EXIT FOR
        END IF
      NEXT

      IF subIdx = -1 THEN
        throwCompilerError "SUB NOT FOUND", ASIS, 0
        parseStatement = 0
        EXIT FUNCTION
      END IF

      currentScopeID = subs(subIdx).ScopeID
      insideSub = 1
      currentSubName$ = subName$ ' Emit jump over SUB
      subs(subIdx).JmpPatchPos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      subs(subIdx).Offset = emitPos

      ' Align stack for internal SUB, preserve ABI non-volatiles, and allocate frame
      emitSubPrologue

      parseStatement = 1
      EXIT FUNCTION

    CASE 0
      IF LEN(firstTok$) > 0 THEN
        firstChar$ = LEFT$(firstTok$, 1)
        IF (firstChar$ >= "A" AND firstChar$ <= "Z") OR (firstChar$ >= "a" AND firstChar$ <= "z") THEN

          assignRes = parseImplicitAssign(startIdx)
          IF assignRes <> -1 THEN
            parseStatement = assignRes
            EXIT FUNCTION
          END IF

          subName$ = UCASE$(firstTok$)
          vIdx = resolveSymbol(subName$)
          IF vIdx <> -1 THEN
            subIdx = symbols(vIdx).SubIndex
          ELSE
            subIdx = -1
          END IF

          IF subIdx <> -1 THEN
            callRes = parseRoutineCall(startIdx, 0)
            IF callRes = 0 OR LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
              tempSuccess = 0
              IF compileStatusMsg$ = "" THEN throwCompilerError "CALL FAILED", ASIS, 0
            ELSE
              tempSuccess = callRes
            END IF
            parseStatement = tempSuccess
            EXIT FUNCTION
          END IF

          tempSuccess = 0
          throwCompilerError "UNRECOGNIZED KEYWORD '" + firstTok$ + "'", ASIS, 0
          parseStatement = tempSuccess
          EXIT FUNCTION
        END IF
      END IF

      tempSuccess = 0
      throwCompilerError "UNRECOGNIZED KEYWORD", ASIS, 0
      parseStatement = tempSuccess
      EXIT FUNCTION

    CASE ELSE
      tempSuccess = 0
      throwCompilerError "UNRECOGNIZED KEYWORD", ASIS, 0
      parseStatement = tempSuccess
      EXIT FUNCTION

  END SELECT ' tVal

END FUNCTION ' parseStatement

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

  ' Process the filtered clipboard and inject directly into the opened array slots
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

  patchOffset = emitPos - (wPos + 1)
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
SUB prepareBinary

  compilePass5GlobalMap

  outputFileIdx = 0

  rwVar$ = " " ' Necessary, do not remove

  ' Save user code, prepend prologue
  userCodeLen = emitPos
  DIM userCode(userCodeLen + 1) AS _UNSIGNED _BYTE
  FOR ii = 0 TO userCodeLen - 1
    userCode(ii) = intermediateCode(ii)
  NEXT
  emitPos = 0

  IF compileHasGraphics = 0 THEN
    userPatchCount = patchCount
    userIatPatchCount = iatPatchCount
    userGfxPatchCount = gfxPatchCount
    userGotoPatchCount = gotoPatchCount
    userCallPatchCount = callPatchCount
    userRtPatchCount = rt.PatchCount
    userSubCount = subCount

    emitPrologue
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    adjustAllPatchOffsets emitPos, userPatchCount, userIatPatchCount, userGfxPatchCount, userGotoPatchCount, userCallPatchCount, userRtPatchCount, userSubCount

    '''' User code
    FOR ii = 0 TO userCodeLen - 1
      intermediateCode(emitPos) = userCode(ii)
      emitPos = emitPos + 1
    NEXT

  ELSE
    '''' Graphics mode
    userPatchCount = patchCount
    userIatPatchCount = iatPatchCount
    userGfxPatchCount = gfxPatchCount
    userGotoPatchCount = gotoPatchCount
    userCallPatchCount = callPatchCount
    userRtPatchCount = rt.PatchCount
    userSubCount = subCount

    IF USE_DIB_SECTION = 1 THEN
      ESCAPETEXT "USE_DIB_SECTION SET TO 1, HARDWARE GRAPHICS NOT SUPPORTED YET"
    ELSE
      emitPrologueWindowSetup
    END IF
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    ' Call emitPrologue to initialize internal heap pointers inside the thread space correctly
    ' emitPrologue automatically allocates the necessary aligned stack frame, so no manual sub rsp is needed here
    emitPrologue
    IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

    adjustAllPatchOffsets emitPos, userPatchCount, userIatPatchCount, userGfxPatchCount, userGotoPatchCount, userCallPatchCount, userRtPatchCount, userSubCount

    '''' User code
    FOR ii = 0 TO userCodeLen - 1
      intermediateCode(emitPos) = userCode(ii)
      emitPos = emitPos + 1
    NEXT

  END IF

  vIdx = resolveSymbol("&END_PROGRAM")
  IF vIdx <> -1 THEN
    symbols(vIdx).DataType = TYPE_LABEL
    symbols(vIdx).Offset = emitPos
  END IF

  '''' Epilogue
  emitEpilogue
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  '''' Compiler runtime helpers
  emitRuntime
  IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN EXIT SUB

  gfxBufTotalSize = 4096 * layout.GfxBufEntrySize

  ' Dedicated layout calculation block
  textLayout.CodeOffset = PE_FILE_HEADER_OFFSET
  textLayout.CodeSize = emitPos
  textLayout.StrBase = textLayout.CodeOffset + textLayout.CodeSize
  textLayout.VarBase = textLayout.StrBase + textLayout.TotalStrSize
  textLayout.DescBase = textLayout.VarBase + textLayout.TotalVarSize
  textLayout.GfxBufBase = textLayout.DescBase + textLayout.TotalDescSize
  textLayout.HwndBase = textLayout.GfxBufBase + gfxBufTotalSize
  textLayout.MemDCBase = textLayout.HwndBase + 8
  textLayout.DIBPtrBase = textLayout.MemDCBase + 8
  textLayout.HBitmapBase = textLayout.DIBPtrBase + 8
  textLayout.FramebufBase = textLayout.HBitmapBase + 8
  textLayout.KbdBufBase = textLayout.FramebufBase + layout.FramebufSize
  textLayout.KbdHeadBase = textLayout.KbdBufBase + 256
  textLayout.KbdTailBase = textLayout.KbdHeadBase + 8
  textLayout.TotalSize = (textLayout.KbdTailBase + 8) - textLayout.CodeOffset

  ' Derive the actual .text raw size and .idata RVA from real layout
  wTextRawSize = (((textLayout.TotalSize) + PE_FILE_ALIGNMENT - 1) \ PE_FILE_ALIGNMENT) * PE_FILE_ALIGNMENT
  localIdataRVA = ((PE_TEXT_RVA + textLayout.TotalSize + PE_SECTION_ALIGNMENT - 1) \ PE_SECTION_ALIGNMENT) * PE_SECTION_ALIGNMENT

  ' Set impTbl.baseRVA before buildImportTable so it uses the correct idata RVA
  impTbl.baseRVA = localIdataRVA
  buildImportTable

  ' Patch the rip-relative instructions in intermediateCode
  FOR ii = 0 TO patchCount - 1
    pOffEmit = patches(ii).Offset
    vIdx = patches(ii).VarIdx

    IF vIdx < 0 THEN

      SELECT CASE vIdx

        CASE TEMP_HEAP_VAR_IDX
          vIdx = internalTempHeapSymbolIdx
        CASE PROCESS_HEAP_VAR_IDX
          vIdx = internalProcessHeapSymbolIdx

      END SELECT ' vIdx

    END IF

    actualVarOffset = textLayout.VarBase + symbols(vIdx).Offset
    varRVA = textFileRVA(actualVarOffset)

    ripAfter = PE_TEXT_VA + pOffEmit + 4
    disp = varRVA - ripAfter

    patch32 pOffEmit, disp
  NEXT

  ' Patch the IAT calls
  FOR ii = 0 TO iatPatchCount - 1
    pOffEmit = iatPatches(ii).Offset
    iatConst = iatPatches(ii).IATIdx
    mappedIdx = impIatFlatIdx(iatConst)

    iatEntryRVA = PE_IMAGE_BASE + impFlatIatRVA(mappedIdx)

    ripAfter = PE_TEXT_VA + pOffEmit + 4
    disp = iatEntryRVA - ripAfter

    patch32 pOffEmit, disp
  NEXT

  ' Patch the graphics calls
  FOR ii = 0 TO gfxPatchCount - 1
    pOffEmit = gfxPatches(ii).Offset
    sIdx = gfxPatches(ii).StrIdx

    SELECT CASE sIdx

      CASE -2
        targetRVA = textFileRVA(textLayout.GfxBufBase)
      CASE -3
        targetRVA = textFileRVA(textLayout.FramebufBase)
      CASE -4
        targetRVA = textFileRVA(textLayout.HwndBase)
      CASE -5
        targetRVA = textFileRVA(textLayout.KbdHeadBase)
      CASE -6
        targetRVA = textFileRVA(textLayout.KbdTailBase)
      CASE -7
        targetRVA = textFileRVA(textLayout.KbdBufBase)
      CASE -8
        targetRVA = textFileRVA(textLayout.MemDCBase)
      CASE -9
        targetRVA = textFileRVA(textLayout.DIBPtrBase)
      CASE -10
        targetRVA = textFileRVA(textLayout.HBitmapBase)
      CASE ELSE
        actualVarOffset = textLayout.VarBase + symbols(sIdx).Offset
        targetRVA = textFileRVA(actualVarOffset)

    END SELECT ' sIdx

    ripAfter = PE_TEXT_VA + pOffEmit + 4
    disp = targetRVA - ripAfter

    patch32 pOffEmit, disp
  NEXT

  ' Patch the goto calls
  FOR ii = 0 TO gotoPatchCount - 1
    pOffEmit = gotoPatches(ii).Offset
    vIdx = gotoPatches(ii).VarIdx
    targetOffset = symbols(vIdx).Offset

    disp = targetOffset - (pOffEmit + 4)
    patch32 pOffEmit, disp
  NEXT

  ' Patch the call patches
  FOR ii = 0 TO callPatchCount - 1
    pOffEmit = callPatches(ii).Offset
    targetName$ = RTRIM$(callPatches(ii).SubName)
    targetOffset = -1
    FOR i2 = 0 TO subCount - 1
      IF RTRIM$(subs(i2).RecordName) = targetName$ THEN
        targetOffset = subs(i2).Offset
        EXIT FOR
      END IF
    NEXT

    IF targetOffset <= 0 THEN
      compileStatusMsg$ = "ERROR: SUB " + targetName$ + " OFFSET UNRESOLVED"
      EXIT SUB
    END IF

    disp = targetOffset - (pOffEmit + 4)
    patch32 pOffEmit, disp
  NEXT

  ' Patch the runtime helper calls
  FOR ii = 0 TO rt.PatchCount - 1
    pOffEmit = rtPatches(ii).Offset
    targetOffset = 0

    IF rtPatches(ii).Routine = RT_STR_ASSIGN THEN
      targetOffset = rt.StrAssignOffset
    END IF
    IF rtPatches(ii).Routine = RT_LINE THEN
      targetOffset = rt.LineOffset
    END IF
    IF rtPatches(ii).Routine = RT_PLOT_PIXEL THEN
      targetOffset = rt.PlotPixelOffset
    END IF
    IF rtPatches(ii).Routine = RT_VEH_HANDLER THEN
      targetOffset = rt.VehHandlerOffset
    END IF
    IF rtPatches(ii).Routine = RT_KEYDOWN THEN
      targetOffset = rt.KeyDownOffset
    END IF

    disp = targetOffset - (pOffEmit + 4)
    patch32 pOffEmit, disp
  NEXT

  '''' PE header + section tables
  writePEHeader wTextRawSize

  '''' Insert compiled statements code (prologue + user code + epilogue + runtime)
  FOR ii = 0 TO emitPos - 1
    outputFile(outputFileIdx) = intermediateCode(ii)
    outputFileIdx = outputFileIdx + 1
  NEXT

  ' Output literal string data correctly packed into StrBase
  arraypadUpTo textLayout.StrBase, 0
  FOR ii = 0 TO symbolCount - 1
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
      ' Skip local variables as they natively reside in the dynamic stack frame
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

  ' Output each numeric variable's slot AND string descriptor pointers
  arraypadUpTo textLayout.VarBase, 0
  FOR ii = 0 TO symbolCount - 1
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
      ' Skip local variables
    ELSE
      IF symbols(ii).IsArray = 2 THEN
        arrayPadNumBytes 8, 0
      ELSE
        IF symbols(ii).DataType = TYPE_DOUBLE AND floatVarData(ii) <> 0 AND symbols(ii).IsArray = 0 THEN
          arrayWrite64F floatVarData(ii)
        ELSE
          IF symbols(ii).DataType = TYPE_SINGLE AND floatVarData(ii) <> 0 AND symbols(ii).IsArray = 0 THEN
            arrayWrite32F floatVarData(ii)
            arrayPadNumBytes 4, 0 ' Ensures correct 8-byte boundaries for the next layout
          ELSE
            IF symbols(ii).DataType = TYPE_STRING THEN
              IF symbols(ii).IsArray = 1 THEN
                searchName$ = "!LEN_" + RTRIM$(symbols(ii).RecordName)
                hVal = hashString(searchName$)
                checkIdx = symHash(hVal)
                lenIdx = -1
                DO WHILE checkIdx <> -1
                  IF RTRIM$(symbols(checkIdx).RecordName) = searchName$ THEN
                    lenIdx = checkIdx
                    EXIT DO
                  END IF
                  checkIdx = symbols(checkIdx).HashNext
                LOOP
                IF lenIdx <> -1 THEN
                  fixedLen = floatVarData(lenIdx)
                ELSE
                  fixedLen = 0
                END IF

                IF fixedLen > 0 THEN
                  arrayPadNumBytes retSymbolByteSize(ii), 32 ' Space character padding
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

  ' Output the initialized String Descriptors in DescBase
  arraypadUpTo textLayout.DescBase, 0
  FOR ii = 0 TO symbolCount - 1
    IF (symbols(ii).IsLocal = 1 AND symbols(ii).IsShared = 0) OR symbols(ii).DataType = TYPE_LABEL THEN
      ' Skip local variables
    ELSE
      IF symbols(ii).DataType = TYPE_STRING AND symbols(ii).IsArray = 0 THEN
        IF strVarData$(ii) <> "" THEN
          strVA = textFileRVA(textLayout.StrBase + symbols(ii).StrOffset)
          strLen = LEN(strVarData$(ii))
          arrayWrite32LE strVA
          arrayWrite32LE 0
          arrayWrite32LE strLen
          arrayWrite32LE 0
          arrayWrite32LE strLen
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

  ' Graphics buffer starts empty, populated at runtime
  arraypadUpTo textLayout.GfxBufBase, 0
  arrayPadNumBytes gfxBufTotalSize, 0

  ' HWND initialized to zero
  arrayWrite32LE 0
  arrayWrite32LE 0

  ' MemDCBase
  arrayWrite32LE 0
  arrayWrite32LE 0

  ' DIBPtrBase
  arrayWrite32LE 0
  arrayWrite32LE 0

  ' HBitmapBase
  arrayWrite32LE 0
  arrayWrite32LE 0

  ' Pad rest of .text to prepare for .idata
  arraypadUpTo PE_FILE_HEADER_OFFSET + wTextRawSize, 0

  '''' Idata section
  writeIdataSection wTextRawSize

END SUB ' prepareBinary

''''''''''''''''''''''''
SUB PrintChr (wPosPixelsX, wPosPixelsY, wStr$, fgClr, bgClr)

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
        IF bgClr <> -1 THEN
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
SUB PrintStr (wPosPixelsX, wPosPixelsY, wStr$, fgClr, bgClr)

  FOR ii = 1 TO LEN(wStr$)
    toSend$ = MID$(wStr$, ii, 1)
    PrintChr wPosPixelsX - 8 + (ii * 8), wPosPixelsY, toSend$, fgClr, bgClr
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

  PrintStr boxStartX + paddingPixels, boxStartY + paddingPixels, text$, wClr, 0

END SUB ' PrintTextLineWithBanners

''''''''''''''''''''''''
SUB processCompileState

  SELECT CASE compileState

    CASE COMP_REFINE
      refineCode 1
      IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN
        compileState = COMP_IDLE
      ELSE
        addStatusMsg "COMPILING (PASS 1-3)..."
        compileState = COMP_COMPILE
        pass4.SubState = 0
      END IF

    CASE COMP_COMPILE
      IF pass4.SubState = 0 THEN
        compRes = compile
        IF compRes = 1 THEN
          addStatusMsg "DISCOVERING SYMBOLS (PASS 3C)..."
          isDummyPass = 1
          pass4.SubState = 1
          pass4.Line = 1
          pass4.Success = 1
        ELSE
          compileState = COMP_IDLE
        END IF
      ELSE
        IF pass4.SubState = 1 THEN
          compilePass4ScanOrEmit
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" OR pass4.Success = 0 THEN
            compileState = COMP_IDLE
          ELSE
            IF pass4.SubState = 2 THEN
              ' Dummy pass complete! Now safely run Pre-Emission Local Layouts!
              compilePass4bLocalVariables

              addStatusMsg "GENERATING CODE (PASS 4+)..."
              isDummyPass = 0
              emitPos = 0
              patchCount = 0
              iatPatchCount = 0
              gfxPatchCount = 0
              gotoPatchCount = 0
              callPatchCount = 0
              rt.PatchCount = 0
              ctrlCount = 0
              tempVarCounter = 0
              crlfSlotIdx = -1 ' FIX: Flush dangling symbol index layout map
              pass4.SubState = 3
              pass4.Line = 1
              pass4.Success = 1
            END IF
          END IF
        ELSE
          IF pass4.SubState = 3 THEN
            compilePass4ScanOrEmit
            IF LEFT$(compileStatusMsg$, 5) = "ERROR" OR pass4.Success = 0 THEN
              compileState = COMP_IDLE
            ELSE
              IF pass4.SubState = 2 THEN
                addStatusMsg "SAVING..."
                compileState = COMP_SAVE
              END IF
            END IF
          END IF
        END IF
      END IF

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

  clickedItem = -1

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
        IF mouse.Released1 AND mouseDownWithinBoxBounds(wPosX + 2, itemY, boxW - 4, itemH) THEN clickedItem = ii
      END IF
      PrintStr wPosX + 8, itemY + 2, dStr$, 15, -1
    ELSE
      PrintStr wPosX + 8, itemY + 2, dStr$, sysColor.gray, -1
    END IF
  NEXT

  IF mouse.Released1 THEN
    IF mouseWithinBoxBounds(wPosX, wPosY, boxW, boxH) AND mouseDownWithinBoxBounds(wPosX, wPosY, boxW, boxH) THEN
      editor.MenuClicked = 1
    END IF
  END IF

  tempRet = clickedItem
  processDropdownMenu = tempRet

END FUNCTION ' processDropdownMenu

''''''''''''''''''''''''
SUB processInput

  kVal = _KEYHIT
  IF kVal = 0 THEN EXIT SUB

  IF editor.Focus = 2 THEN
    ' Ctrl+C (Copy)
    IF kVal = 3 OR ((kVal = 99 OR kVal = 67) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      IF editor.StatusSelectedIndex <> -1 THEN
        _CLIPBOARD$ = statusMsg$(editor.StatusSelectedIndex)
      END IF
      kVal = 0
    END IF

    ' Ctrl+X (Cut) - Treat as copy for status bar
    IF kVal = 24 OR ((kVal = 120 OR kVal = 88) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      IF editor.StatusSelectedIndex <> -1 THEN
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

    ' Ctrl+F (Find)
    IF kVal = 6 OR ((kVal = 102 OR kVal = 70) AND (_KEYDOWN(100306) OR _KEYDOWN(100305))) THEN
      kVal = 0
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
          FOR ii = editor.CursorY TO EDITOR_LINE_MAX - 1
            editorText$(ii) = editorText$(ii + 1)
          NEXT
          editorText$(EDITOR_LINE_MAX) = ""
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
          FOR ii = editor.CursorY + 1 TO EDITOR_LINE_MAX - 1
            editorText$(ii) = editorText$(ii + 1)
          NEXT
          editorText$(EDITOR_LINE_MAX) = ""
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
        FOR ii = EDITOR_LINE_MAX - 1 TO editor.CursorY + 1 STEP -1
          editorText$(ii + 1) = editorText$(ii)
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
SUB pushStatusMsg (wStr$)

  IF statusMsgCount < 1000 THEN
    statusMsg$(statusMsgCount) = wStr$
    statusMsgCount = statusMsgCount + 1
  ELSE
    FOR ii = 0 TO 998
      statusMsg$(ii) = statusMsg$(ii + 1)
    NEXT
    statusMsg$(999) = wStr$
  END IF

  statusBoxH = 38
  maxLines = (statusBoxH - 8) \ 10
  IF statusMsgCount > maxLines THEN
    editor.StatusScrollY = statusMsgCount - maxLines
  ELSE
    editor.StatusScrollY = 0
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
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 48, "MSX:" + cTrNum$(mouse.PosX), 15, -1
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 36, "MSY:" + cTrNum$(mouse.PosY), 15, -1
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 24, "CX:" + cTrNum$(editor.CursorX), 15, -1
  PrintStr SCREENSIZEX - 72, SCREENSIZEY - 12, "CY:" + cTrNum$(editor.CursorY), 15, -1

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

  strDeclCount = 0

  refCount = 0
  activeScope = 0
  scopeCounter = 0

  uiSubCount = 0

  ' Quick prescan for #CLASSIC to ensure the editor accurately respects duck typing rules during refinement.
  ' We do this here because refineCode runs before compilePass2Scan during an F5 compile, meaning
  ' compileClassicMode would otherwise be 0, incorrectly enforcing Standard Mode rules on duck-typed code.
  compileClassicMode = 0
  FOR iy = 1 TO editor.LastLine
    tempScan$ = UCASE$(LTRIM$(RTRIM$(editorText$(iy))))
    IF LEFT$(tempScan$, 8) = "#CLASSIC" THEN
      compileClassicMode = 1
      EXIT FOR
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
      pendingStrIdx = -1
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
                IF kwVal = TOK_AS THEN
                  asMode = 1
                  IF lastVarBase$ <> "" THEN
                    foundIdx = -1
                    FOR iStr = 0 TO strDeclCount - 1
                      IF strDeclName$(iStr) = lastVarBase$ AND strDeclScope(iStr) = activeScope THEN
                        foundIdx = iStr
                        EXIT FOR
                      END IF
                    NEXT
                    IF foundIdx = -1 AND strDeclCount < 1024 THEN
                      foundIdx = strDeclCount
                      strDeclName$(foundIdx) = lastVarBase$
                      strDeclScope(foundIdx) = activeScope
                      strDeclCount = strDeclCount + 1
                    END IF
                    IF foundIdx <> -1 THEN
                      strDeclType(foundIdx) = 0 ' Suspend initially
                      pendingStrIdx = foundIdx
                    END IF
                  END IF
                ELSE
                  IF kwVal = TOK_DSTRING AND asMode = 1 THEN
                    asMode = 0
                    IF pendingStrIdx <> -1 THEN
                      strDeclType(pendingStrIdx) = 1 ' DSTRING forces $
                      pendingStrIdx = -1
                    END IF
                  ELSE
                    IF kwVal = TOK_STRING AND asMode = 1 THEN
                      asMode = 3 ' Waiting for *
                    ELSE
                      asMode = 0
                      pendingStrIdx = -1
                    END IF
                  END IF
                END IF

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

                IF asMode = 4 THEN
                  ' Valid identifier used as length (e.g. constant)
                  asMode = 0
                  IF pendingStrIdx <> -1 THEN
                    IF lastVarSuffix$ = "$" THEN
                      strDeclType(pendingStrIdx) = 1
                    ELSE
                      strDeclType(pendingStrIdx) = 2
                    END IF
                    pendingStrIdx = -1
                  END IF
                ELSE
                  asMode = 0
                  pendingStrIdx = -1
                END IF

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
                  foundIdx = -1
                  FOR iStr = 0 TO strDeclCount - 1
                    IF strDeclName$(iStr) = baseName$ AND strDeclScope(iStr) = activeScope THEN
                      foundIdx = iStr
                      EXIT FOR
                    END IF
                  NEXT
                  IF foundIdx = -1 AND strDeclCount < 1024 THEN
                    foundIdx = strDeclCount
                    strDeclName$(foundIdx) = baseName$
                    strDeclScope(foundIdx) = activeScope
                    strDeclType(foundIdx) = 1 ' Mark as Requires $
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

                vIdx = -1
                uIdent$ = UCASE$(ident$)

                FOR ii = 0 TO refCount - 1
                  IF UCASE$(refName$(ii)) = uIdent$ THEN
                    IF refScope(ii) = activeScope THEN
                      vIdx = ii
                      EXIT FOR
                    END IF
                  END IF
                NEXT

                IF vIdx = -1 AND activeScope > 0 THEN
                  FOR ii = 0 TO refCount - 1
                    IF UCASE$(refName$(ii)) = uIdent$ THEN
                      IF refScope(ii) = 0 THEN
                        vIdx = ii
                        EXIT FOR
                      END IF
                    END IF
                  NEXT
                END IF

                IF isValidLine = 1 THEN
                  IF vIdx = -1 THEN
                    IF refCount < MAX_SYMBOLS THEN
                      vIdx = refCount
                      refName$(vIdx) = ident$
                      refScope(vIdx) = activeScope
                      refCount = refCount + 1
                    END IF
                    newLine$ = newLine$ + ident$
                  ELSE
                    newLine$ = newLine$ + refName$(vIdx)
                  END IF
                ELSE
                  IF vIdx = -1 THEN
                    newLine$ = newLine$ + ident$
                  ELSE
                    newLine$ = newLine$ + refName$(vIdx)
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

              IF ch$ = "*" AND asMode = 3 THEN
                asMode = 4 ' Waiting for length
              ELSE
                IF ch$ <> " " AND ch$ <> CHR$(9) THEN
                  IF asMode = 4 THEN
                    ' If we see a valid number, we successfully found our length
                    IF ch$ >= "0" AND ch$ <= "9" THEN
                      asMode = 0
                      IF pendingStrIdx <> -1 THEN
                        IF lastVarSuffix$ = "$" THEN
                          strDeclType(pendingStrIdx) = 1
                        ELSE
                          strDeclType(pendingStrIdx) = 2
                        END IF
                        pendingStrIdx = -1
                      END IF
                    ELSE
                      ' Garbage found! Abort commit and leave the variable Suspended
                      asMode = 0
                      pendingStrIdx = -1
                    END IF
                  ELSE
                    asMode = 0
                    pendingStrIdx = -1
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

  DIM dType AS LONG
  DIM vIdx AS LONG
  DIM isExp AS LONG
  DIM suffix$
  DIM firstChar$
  DIM charIdx AS LONG
  DIM hVal AS LONG
  DIM searchName$
  DIM conflictIdx AS LONG

  searchName$ = UCASE$(vName$)
  vIdx = findSymbol(searchName$)
  IF vIdx <> -1 THEN
    resolveSymbol = vIdx
    EXIT FUNCTION
  END IF

  dType = TYPE_SINGLE
  isExp = 0

  firstChar$ = LEFT$(searchName$, 1)
  IF firstChar$ = "!" OR firstChar$ = "~" THEN
    dType = TYPE_INTEGER64
    isExp = 1
  ELSE
    IF firstChar$ = "&" OR firstChar$ = "%" THEN
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
      conflictIdx = findSymbol(LEFT$(searchName$, LEN(searchName$) - 1))
      IF conflictIdx <> -1 THEN
        IF symbols(conflictIdx).DataType <> TYPE_STRING THEN
          throwCompilerError "STRING NAME CONFLICT", ASIS, 0
          resolveSymbol = -1
          EXIT FUNCTION
        END IF
      END IF
    ELSE
      conflictIdx = findSymbol(searchName$ + "$")
      IF conflictIdx <> -1 THEN
        throwCompilerError "STRING NAME CONFLICT", ASIS, 0
        resolveSymbol = -1
        EXIT FUNCTION
      END IF
    END IF
  END IF

  IF symbolCount >= MAX_SYMBOLS THEN
    throwCompilerError "SYMBOL LIMIT", ASIS, 0
    resolveSymbol = -1
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
  symbols(vIdx).SubIndex = -1
  symbols(vIdx).UDTIndex = -1
  symbols(vIdx).IsExplicit = isExp
  symbols(vIdx).alreadyParsed = 0
  symbols(vIdx).IsLocal = 0

  IF currentScopeID > 0 AND firstChar$ <> "!" AND firstChar$ <> "&" AND firstChar$ <> "~" AND firstChar$ <> "%" THEN
    symbols(vIdx).IsLocal = 1
  END IF
  symbols(vIdx).LocalOffset = 0
  symbols(vIdx).DescOffset = 0
  symbols(vIdx).StrOffset = 0

  hVal = hashString(searchName$)
  symbols(vIdx).HashNext = symHash(hVal)
  symHash(hVal) = vIdx

  symbolCount = symbolCount + 1
  resolveSymbol = vIdx

END FUNCTION ' resolveSymbol

''''''''''''''''''''''''
SUB retCoordinateBoundaries (passStartIdx, passEndIdx, outStart, outComma, outEnd)

  outStart = passStartIdx
  outEnd = passEndIdx

  ' Strip surrounding parentheses if they exist to isolate the coordinate arguments
  IF retTokenVal(lineTokens$(outStart)) = 256 + ASC("(") THEN
    IF retTokenVal(lineTokens$(outEnd)) = 256 + ASC(")") THEN
      outStart = outStart + 1
      outEnd = outEnd - 1
    END IF
  END IF

  outComma = -1
  pDepth = 0
  FOR ii = outStart TO outEnd
    tVal = retTokenVal(lineTokens$(ii))
    IF tVal = 256 + ASC("(") THEN pDepth = pDepth + 1
    IF tVal = 256 + ASC(")") THEN pDepth = pDepth - 1
    IF pDepth = 0 AND tVal = 256 + ASC(",") THEN
      outComma = ii
      EXIT SUB
    END IF
  NEXT

END SUB ' retCoordinateBoundaries

''''''''''''''''''''''''
FUNCTION retEditorSelection$

  IF editor.SelectStartY < editor.CursorY OR (editor.SelectStartY = editor.CursorY AND editor.SelectStartX < editor.CursorX) THEN
    startY = editor.SelectStartY: startX = editor.SelectStartX
    endY = editor.CursorY: endX = editor.CursorX
  ELSE
    startY = editor.CursorY: startX = editor.CursorX
    endY = editor.SelectStartY: endX = editor.SelectStartX
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
FUNCTION retHighByte (wVal)

  ' Returns the left byte of a two-byte value
  retHighByte = shRight(wVal, 8)

END FUNCTION ' retHighByte

''''''''''''''''''''''''
FUNCTION retIatConstByName (wName$)

  tempRet = IAT_INVALID

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
    CASE "CreateCompatibleBitmap": tempRet = IAT_CREATECOMPATIBLEBITMAP
    CASE "CreateCompatibleDC": tempRet = IAT_CREATECOMPATIBLEDC
    CASE "CreateDIBSection": tempRet = IAT_CREATEDIBSECTION
    CASE "CreateFontA": tempRet = IAT_CREATEFONTA
    CASE "CreateThread": tempRet = IAT_CREATETHREAD
    CASE "DeleteDC": tempRet = IAT_DELETEDC
    CASE "DeleteObject": tempRet = IAT_DELETEOBJECT
    CASE "DwmSetWindowAttribute": tempRet = IAT_DWMSETWINDOWATTRIBUTE
    CASE "EndPaint": tempRet = IAT_ENDPAINT
    CASE "ExitThread": tempRet = IAT_EXITTHREAD
    CASE "GetAsyncKeyState": tempRet = IAT_GETASYNCKEYSTATE
    CASE "GetProcessHeap": tempRet = IAT_GETPROCESSHEAP
    CASE "GetStockObject": tempRet = IAT_GETSTOCKOBJECT
    CASE "HeapAlloc": tempRet = IAT_HEAPALLOC
    CASE "HeapFree": tempRet = IAT_HEAPFREE
    CASE "InvalidateRect": tempRet = IAT_INVALIDATERECT
    CASE "LoadCursorA": tempRet = IAT_LOADCURSORA
    CASE "pow": tempRet = IAT_POW
    CASE "RtlMoveMemory": tempRet = IAT_RTLMOVEMEMORY
    CASE "SelectObject": tempRet = IAT_SELECTOBJECT
    CASE "SetBkColor": tempRet = IAT_SETBKCOLOR
    CASE "SetConsoleCursorPosition": tempRet = IAT_SETCONSOLECURSORPOSITION
    CASE "SetConsoleTextAttribute": tempRet = IAT_SETCONSOLETEXTATTRIBUTE
    CASE "SetDIBColorTable": tempRet = IAT_SETDIBCOLORTABLE
    CASE "SetPixel": tempRet = IAT_SETPIXEL
    CASE "SetTextColor": tempRet = IAT_SETTEXTCOLOR
    CASE "Sleep": tempRet = IAT_SLEEP
    CASE "sprintf": tempRet = IAT_SPRINTF
    CASE "StretchBlt": tempRet = IAT_STRETCHBLT
    CASE "TextOutA": tempRet = IAT_TEXTOUTA
    CASE ELSE: tempRet = IAT_INVALID

  END SELECT ' wName$

  retIatConstByName = tempRet

END FUNCTION ' retIatConstByName

''''''''''''''''''''''''
FUNCTION retLineNumberStr$

  ' Returns the current line number as a formatted string
  retLineNumberStr$ = LTRIM$(RTRIM$(STR$(currentLineNumber)))

END FUNCTION ' retLineNumberStr$

''''''''''''''''''''''''
FUNCTION retSymbolByteSize (vIdx)

  DIM paddedSize AS LONG
  DIM remainder AS LONG
  DIM dt AS LONG
  DIM fixedLen AS LONG
  DIM lenIdx AS LONG

  dt = symbols(vIdx).DataType

  IF dt = TYPE_UNDEFINED THEN
    IF symbols(vIdx).SubIndex <> -1 THEN
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
        searchName$ = "!LEN_" + RTRIM$(symbols(vIdx).RecordName)
        hVal = hashString(searchName$)
        checkIdx = symHash(hVal)
        lenIdx = -1
        DO WHILE checkIdx <> -1
          IF RTRIM$(symbols(checkIdx).RecordName) = searchName$ THEN
            lenIdx = checkIdx
            EXIT DO
          END IF
          checkIdx = symbols(checkIdx).HashNext
        LOOP

        IF lenIdx <> -1 THEN
          fixedLen = floatVarData(lenIdx)
        ELSE
          fixedLen = 0
        END IF

        IF fixedLen > 0 THEN
          paddedSize = symbols(vIdx).Size * fixedLen
          remainder = paddedSize MOD 8
          IF remainder <> 0 THEN paddedSize = paddedSize + (8 - remainder)
        ELSE
          paddedSize = symbols(vIdx).Size * 8
        END IF
      ELSE
        ' Standalone Strings
        IF symbols(vIdx).IsLocal = 1 AND symbols(vIdx).IsShared = 0 THEN
          paddedSize = 24 ' Local strings put the 24-byte descriptor inline on the stack
        ELSE
          paddedSize = 8 ' Global strings just put an 8-byte pointer in VarBase
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

  tempRet$ = wTok$
  tVal = retTokenVal(wTok$)
  IF tVal <> 0 THEN
    IF voc(tVal).text <> "" THEN
      tempRet$ = voc(tVal).text
    END IF
  END IF

  retTokenText$ = tempRet$

END FUNCTION ' retTokenText$

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
    PrintStr boxX + (boxW \ 2) - 44, boxY + 3, "SEARCH FIND", 14, -1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    closeBtnW = 15
    closeBtnH = 13
    closeBtnX = boxX + boxW - closeBtnW
    closeBtnY = boxY
    drawBorderBox closeBtnX, closeBtnY, closeBtnW, closeBtnH, 15, editor.CloseClr
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, -1

    IF mouse.Released1 THEN
      IF mouseWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) AND mouseDownWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
        EXIT DO
      END IF
    END IF

    ' Input box
    inputBoxX = boxX + 16
    inputBoxY = boxY + 24
    inputBoxW = boxW - 32
    inputBoxH = 16
    drawBorderBox inputBoxX, inputBoxY, inputBoxW, inputBoxH, 15, 0

    ' Draw text
    PrintStr inputBoxX + 4, inputBoxY + 4, editorSearchQuery$ + "_", 15, -1

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

    rFinal = ((rOrig + 2) \ 4) * 4
    gFinal = ((gOrig + 2) \ 4) * 4
    bFinal = ((bOrig + 2) \ 4) * 4

    _PALETTECOLOR ii, _RGB32(rFinal, gFinal, bFinal)
  NEXT

END SUB ' setPalettes256

''''''''''''''''''''''''
FUNCTION shRight (wVal, wDistance) ' Binary shift right

  IF wVal < 0 THEN ESCAPE 3211

  SELECT CASE wDistance

    CASE 1
      shRight = wVal \ 2
      EXIT FUNCTION
    CASE 2
      shRight = wVal \ 4
      EXIT FUNCTION
    CASE 3
      shRight = wVal \ 8
      EXIT FUNCTION
    CASE 4
      shRight = wVal \ 16
      EXIT FUNCTION
    CASE 5
      shRight = wVal \ 32
      EXIT FUNCTION
    CASE 6
      shRight = wVal \ 64
      EXIT FUNCTION
    CASE 7
      shRight = wVal \ 128
      EXIT FUNCTION
    CASE 8
      shRight = wVal \ 256
      EXIT FUNCTION

    CASE ELSE

      shRight = wVal ' No change
      EXIT FUNCTION

  END SELECT ' wDistance

END FUNCTION ' shRight

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
    ESCAPETEXT "throw compiler error not ready yet with withfailed"
  END IF

END SUB ' throwCompilerError

''''''''''''''''''''''''
SUB tasm_DoMath (opCmd AS LONG, dest$, src1$, src2$)

  ' tasm_ functions are back end functions designed to be called by tiraEndAndProcess, or another tasm_ function
  ' These functions do not sit between a tiraStart and a tiraEndAndProcess. They can output raw assembly

  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM targetMode AS LONG
  DIM resIsFloat AS LONG
  DIM concatIdx AS INTEGER

  IF opCmd = TC_CONCAT THEN
    tasm_LoadOperand src1$, 0, isFloat1
    tasm_LoadOperand src2$, 3, isFloat2

    ff = genLoadStringDesc(0, 12, 13)
    ff = genLoadStringDesc(3, 10, 11)

    ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)

    ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 13, 64)
    ff = opALU(ALU_ADD, OP_TYPE_REG, 8, OP_TYPE_REG, 11, 64)

    ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_REG, 8, 64)
    ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

    genBlockTransfer 12, 7, 13
    genBlockTransfer 10, 7, 11

    ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_IMM, 24, 64)
    ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 14, 64)
    ff = opMov(OP_TYPE_MEM_REG_DISP8, 7 + (8 * 256), OP_TYPE_REG, 8, 64)
    ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 7, 64, TEMP_HEAP_VAR_IDX)

    ff = opMov(OP_TYPE_REG, 0, OP_TYPE_REG, 7, 64)
    tasm_StoreOperand dest$, 0, 0
    EXIT SUB
  END IF

  tasm_LoadOperand src1$, 0, isFloat1
  tasm_LoadOperand src2$, 3, isFloat2

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
      ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 16, 64)
      ff = genAlignedCall(IAT_POW, 13, DEFAULT)
      ff = opALU(ALU_ADD, OP_TYPE_REG, 4, OP_TYPE_IMM, 16, 64)
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
        opExtend EXTEND_CQO
        ff = opUnary(UNARY_IDIV, OP_TYPE_REG, 3, 64)
      CASE TC_AND: ff = opALU(ALU_AND, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)
      CASE TC_OR: ff = opALU(ALU_OR, OP_TYPE_REG, 0, OP_TYPE_REG, 3, 64)

    END SELECT ' opCmd

    tasm_StoreOperand dest$, 0, 0
  END IF

END SUB ' tasm_DoMath

''''''''''''''''''''''''
SUB tasm_DoShift (opCmd AS LONG, dest$, src1$, src2$)

  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM opMode AS LONG

  tasm_LoadOperand src1$, 0, isFloat1
  tasm_LoadOperand src2$, 1, isFloat2

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

  tasm_StoreOperand dest$, 0, 0

END SUB ' tasm_DoShift

''''''''''''''''''''''''
SUB tasm_DoUnary (opCmd AS LONG, dest$, src$)

  DIM isFloat AS LONG
  DIM opMode AS LONG

  tasm_LoadOperand src$, 0, isFloat

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
SUB tasm_Intrinsic (tokVal AS LONG, destVar$, arg1$, arg2$, arg3$)

  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM isFloat3 AS LONG
  DIM opMode AS LONG

  SELECT CASE tokVal

    CASE TOK_INKEYF
      ' Allocate 1 byte from Temp Heap
      ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)

      inkeyLoopStart = emitPos
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)
      ff = opMov(OP_TYPE_REG, 13, OP_TYPE_REG, 4, 64)
      ff = opALU(ALU_AND, OP_TYPE_REG, 4, OP_TYPE_IMM, -16, 64)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 4, OP_TYPE_IMM, 32, 64)
      ff = opCall(IAT_GETASYNCKEYSTATE, CALLMODE_IAT)
      ff = opMov(OP_TYPE_REG, 4, OP_TYPE_REG, 13, 64)

      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)
      jmpNextPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_IMM, 1, 64)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 96, 8)
      jmpSkipNumpadA1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 105, 8)
      jmpSkipNumpadA2 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 15, OP_TYPE_IMM, 48, 8)
      patch8 jmpSkipNumpadA1
      patch8 jmpSkipNumpadA2

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 37, 8)
      jmpNotLeft = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 52, 8)
      jmpMapDone1 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotLeft

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 38, 8)
      jmpNotUp = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 56, 8)
      jmpMapDone2 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotUp

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 39, 8)
      jmpNotRight = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 54, 8)
      jmpMapDone3 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotRight

      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 40, 8)
      jmpNotDown = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 50, 8)
      jmpMapDone4 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      patch8 jmpNotDown

      patch8 jmpMapDone1
      patch8 jmpMapDone2
      patch8 jmpMapDone3
      patch8 jmpMapDone4

      ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 15, 8)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)
      jmpDonePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      patch8 jmpNextPos
      opIncReg 15, 64
      ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)
      ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, inkeyLoopStart, JCC_TYPE_NEAR)

      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 0, 64)

      patch8 jmpDonePos
      ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 7, 64, TEMP_HEAP_VAR_IDX)
      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 1)

    CASE TOK_INKEY
      IF compileHasGraphics = 1 THEN
        ff = genSymbolRouteMov(OP_TYPE_REG, 7, OP_TYPE_MEM_RIP, 0, 64, TEMP_HEAP_VAR_IDX)
        ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)

        addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -5, 0
        ff = opMov(OP_TYPE_REG, 10, OP_TYPE_MEM_REG, 0, 32)
        addPatch PATCH_GFX, opLea(OP_TYPE_REG, 2, OP_TYPE_MEM_RIP, 0, 64), -6, 0
        ff = opMov(OP_TYPE_REG, 11, OP_TYPE_MEM_REG, 2, 32)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 10, OP_TYPE_REG, 11, 32)
        jmpEmptyPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

        addPatch PATCH_GFX, opLea(OP_TYPE_REG, 1, OP_TYPE_MEM_RIP, 0, 64), -7, 0
        ff = opMov_SIB(0, OP_TYPE_REG, 8, 1, 11, 1, 0, MODE_MOVZX32_8)
        opIncReg 11, 32
        ff = opALU(ALU_AND, OP_TYPE_REG, 11, OP_TYPE_IMM, 255, 32)
        ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 11, 32)
        ff = opALU(ALU_SUB, OP_TYPE_REG, 7, OP_TYPE_IMM, 1, 64)
        ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 8, 8)
        ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)
        jmpDonePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

        patch8 jmpEmptyPos
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 0, 64)

        patch8 jmpDonePos
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 7, 64, TEMP_HEAP_VAR_IDX)
        ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 1)
      ELSE
        ff = genAllocTempMemory(OP_TYPE_IMM, 1, 7)
        ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 8, 64)

        inkeyLoopStart = emitPos
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 15, 64)
        ff = genAlignedCall(IAT_GETASYNCKEYSTATE, 13, DEFAULT)

        ff = opTest(OP_TYPE_REG, 0, OP_TYPE_IMM, &H8000, 16)
        jmpNextPos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 96, 8)
        jmpSkipNumpadA1 = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 105, 8)
        jmpSkipNumpadA2 = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opALU(ALU_SUB, OP_TYPE_REG, 15, OP_TYPE_IMM, 48, 8)
        patch8 jmpSkipNumpadA1
        patch8 jmpSkipNumpadA2

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 37, 8)
        jmpNotLeft = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 52, 8)
        jmpMapDone1 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotLeft

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 38, 8)
        jmpNotUp = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 56, 8)
        jmpMapDone2 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotUp

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 39, 8)
        jmpNotRight = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 54, 8)
        jmpMapDone3 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotRight

        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 40, 8)
        jmpNotDown = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        ff = opMov(OP_TYPE_REG, 15, OP_TYPE_IMM, 50, 8)
        jmpMapDone4 = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        patch8 jmpNotDown

        patch8 jmpMapDone1
        patch8 jmpMapDone2
        patch8 jmpMapDone3
        patch8 jmpMapDone4

        ff = opMov(OP_TYPE_MEM_REG, 14, OP_TYPE_REG, 15, 8)
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)
        jmpDonePos = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

        patch8 jmpNextPos
        opIncReg 15, 64
        ff = opALU(ALU_CMP, OP_TYPE_REG, 15, OP_TYPE_IMM, 255, 64)
        ff = opJcc(JCC_JL, JCC_MODE_BACKWARD, inkeyLoopStart, JCC_TYPE_NEAR)

        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 0, 64)

        patch8 jmpDonePos
        ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
        ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 1)
      END IF

    CASE TOK_STR
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genAllocTempMemory(OP_TYPE_IMM, 32, 7)
      ff = opMov(OP_TYPE_REG, 10, OP_TYPE_REG, 7, 64)
      ff = opALU(ALU_ADD, OP_TYPE_REG, 10, OP_TYPE_IMM, 31, 64)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 10, 64)

      ff = opALU(ALU_XOR, OP_TYPE_REG, 12, OP_TYPE_REG, 12, 64)
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
      jmpPos = opJcc(JCC_JNS, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      opIncReg 12, 64
      ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)

      patch8 jmpPos
      ff = opMov(OP_TYPE_REG, 11, OP_TYPE_IMM, 10, 64)

      itoaLoopStartStr = emitPos
      ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)
      ff = opUnary(UNARY_DIV, OP_TYPE_REG, 11, 64)
      ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_IMM, 48, 8)
      opDecReg 10, 64
      ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_REG, 2, 8)
      ff = opTest(OP_TYPE_REG, 0, OP_TYPE_REG, 0, 64)
      ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, itoaLoopStartStr, JCC_TYPE_SHORT)

      opDecReg 10, 64
      ff = opTest(OP_TYPE_REG, 12, OP_TYPE_REG, 12, 64)
      jmpSpace = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_IMM, 45, 8)
      jmpDoneStr = opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      patch8 jmpSpace
      ff = opMov(OP_TYPE_MEM_REG, 10, OP_TYPE_IMM, 32, 8)

      patch8 jmpDoneStr
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 14, 64)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 8, OP_TYPE_REG, 10, 64)
      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 10, 8)

    CASE TOK_VAL
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genLoadStringDesc(0, 6, 1)

      ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG, 0, 32)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 7, OP_TYPE_REG, 7, 32)

      skipSpaceStart = emitPos
      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpNumDone1Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ff = opALU(ALU_CMP, OP_TYPE_MEM_REG, 6, OP_TYPE_IMM, 32, 8)
      jmpCheckSignPos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      opIncReg 6, 64
      opDecReg 1, 64
      ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, skipSpaceStart, JCC_TYPE_SHORT)

      patch8 jmpCheckSignPos
      ff = opALU(ALU_CMP, OP_TYPE_MEM_REG, 6, OP_TYPE_IMM, 45, 8)
      jmpNumLoopPos = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      opIncReg 7, 64
      opIncReg 6, 64
      opDecReg 1, 64

      numLoopStart = emitPos
      patch8 jmpNumLoopPos

      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpNumDone2Pos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR)

      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_MEM_REG, 6, MODE_MOVZX64_8)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 2, OP_TYPE_IMM, 48, 8)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_IMM, 9, 8)
      jmpNumSkipPos = opJcc(JCC_JA, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opImul(0, OP_TYPE_REG, 0, 10, MODE_IMUL64_IMM)
      ff = opALU(ALU_ADD, OP_TYPE_REG, 0, OP_TYPE_REG_ALT, 2, 64)

      patch8 jmpNumSkipPos
      opIncReg 6, 64
      opDecReg 1, 64
      ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, numLoopStart, JCC_TYPE_NEAR)

      patch32 jmpNumDone1Pos, emitPos - (jmpNumDone1Pos + 4)
      patch32 jmpNumDone2Pos, emitPos - (jmpNumDone2Pos + 4)

      ff = opTest(OP_TYPE_REG, 7, OP_TYPE_REG, 7, 64)
      jmpNumStorePos = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opUnary(UNARY_NEG, OP_TYPE_REG, 0, 64)

      patch8 jmpNumStorePos
      tasm_StoreOperand destVar$, 0, 0

    CASE TOK_LTRIM
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genLoadStringDesc(0, 12, 13)

      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)
      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)

      ltrimLoopStart = emitPos
      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpDonePos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 6, MODE_MOVZX32_8)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 32, 32)
      jmpIsSpace1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 9, 32)
      jmpNotSpace = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      patch8 jmpIsSpace1
      opIncReg 6, 64
      opDecReg 1, 64
      ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, ltrimLoopStart, JCC_TYPE_SHORT)

      patch8 jmpDonePos
      patch8 jmpNotSpace

      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 6, 1)

    CASE TOK_RTRIM
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genLoadStringDesc(0, 12, 13)

      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)
      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)

      rtrimLoopStart = emitPos
      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpRDonePos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 6, 64)
      ff = opALU(ALU_ADD, OP_TYPE_REG, 2, OP_TYPE_REG, 1, 64)
      opDecReg 2, 64

      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_MEM_REG, 2, MODE_MOVZX32_8)
      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 32, 32)
      jmpRIsSpace1 = opJcc(JCC_JE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_IMM, 9, 32)
      jmpRNotSpace = opJcc(JCC_JNE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      patch8 jmpRIsSpace1
      opDecReg 1, 64
      ff = opJcc(JCC_JMP, JCC_MODE_BACKWARD, rtrimLoopStart, JCC_TYPE_SHORT)

      patch8 jmpRDonePos
      patch8 jmpRNotSpace

      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 6, 1)

    CASE TOK_UCASE
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genLoadStringDesc(0, 12, 13)

      ff = genAllocTempMemory(OP_TYPE_REG, 13, 7)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      ff = opMov(OP_TYPE_REG, 6, OP_TYPE_REG, 12, 64)
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_REG, 13, 64)

      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpDoneOffset = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ucaseLoopStart = emitPos
      opString STR_LODS, REP_NONE, 8
      ff = opALU(ALU_CMP, OP_TYPE_ACC, 0, OP_TYPE_IMM, 97, 8)
      jmpStore1Pos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_CMP, OP_TYPE_ACC, 0, OP_TYPE_IMM, 122, 8)
      jmpStore2Pos = opJcc(JCC_JG, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)

      ff = opALU(ALU_SUB, OP_TYPE_ACC, 0, OP_TYPE_IMM, 32, 8)

      patch8 jmpStore1Pos
      patch8 jmpStore2Pos

      opString STR_STOS, REP_NONE, 8
      opDecReg 1, 64
      ff = opJcc(JCC_JNE, JCC_MODE_BACKWARD, ucaseLoopStart, JCC_TYPE_SHORT)

      patch8 jmpDoneOffset
      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 13)

    CASE TOK_ASC
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genLoadStringDesc(0, 6, 1)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 0, OP_TYPE_REG_ALT, 0, 64)
      ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
      jmpSkipLodsbPos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      opString STR_LODS, REP_NONE, 8
      patch8 jmpSkipLodsbPos
      tasm_StoreOperand destVar$, 0, 0

    CASE TOK_CHR
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = genAllocTempMemory(OP_TYPE_IMM, 1, 7)
      ff = opMov(OP_TYPE_MEM_REG, 7, OP_TYPE_REG, 0, 8)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      ff = opMov(OP_TYPE_REG, 1, OP_TYPE_IMM, 1, 64)
      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 1)

    CASE TOK_LEN
      tasm_LoadOperand arg1$, 0, isFloat1
      ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG_DISP8, 0 + (8 * 256), 64)
      tasm_StoreOperand destVar$, 0, 0

    CASE TOK_INT
      tasm_LoadOperand arg1$, 0, isFloat1
      IF isFloat1 > 0 THEN
        opMode = MODE_SSE_DOUBLE: IF isFloat1 = 1 THEN opMode = MODE_SSE_SINGLE
        ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 0, opMode)
        ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
        ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 2, OP_TYPE_REG, 0, opMode)
        ff = opSSE(SSE_UCOMI, OP_TYPE_REG, 1, OP_TYPE_REG, 2, opMode)
        jmpSkipDecPos = opJcc(JCC_JAE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
        opDecReg 0, 64
        patch8 jmpSkipDecPos
      END IF
      tasm_StoreOperand destVar$, 0, 0

    CASE TOK_ATN
      tasm_LoadOperand arg1$, 0, isFloat1
      IF isFloat1 = 0 THEN
        ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
      ELSEIF isFloat1 = 1 THEN
        ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
      END IF
      opPushReg 13
      ff = genAlignedCall(IAT_ATAN, 13, DEFAULT)
      opPopReg 13
      tasm_StoreOperand destVar$, 0, 2

    CASE TOK_MID
      tasm_LoadOperand arg1$, 0, isFloat1
      tasm_LoadOperand arg2$, 2, isFloat2
      tasm_LoadOperand arg3$, 8, isFloat3

      ff = genLoadStringDesc(0, 6, 1)

      opDecReg 2, 64
      ff = opTest(OP_TYPE_REG, 2, OP_TYPE_REG, 2, 64)
      jmpSkipXorPos = opJcc(JCC_JNS, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)
      patch8 jmpSkipXorPos

      ff = opALU(ALU_CMP, OP_TYPE_REG, 2, OP_TYPE_REG_ALT, 1, 64)
      jmpSkipMovPos = opJcc(JCC_JL, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 1, 64)
      patch8 jmpSkipMovPos

      ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_REG_ALT, 2, 64)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 1, OP_TYPE_REG, 2, 64)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 1, OP_TYPE_REG_ALT, 8, 64)
      jmpSkipClampPos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
      patch8 jmpSkipClampPos

      ff = genAllocTempMemory(OP_TYPE_REG, 8, 7)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      genBlockTransfer 6, 7, 8

      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 8)

    CASE TOK_LEFT
      tasm_LoadOperand arg1$, 0, isFloat1
      tasm_LoadOperand arg2$, 8, isFloat2

      ff = genLoadStringDesc(0, 6, 1)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
      jmpSkipClamp1Pos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
      patch8 jmpSkipClamp1Pos

      ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
      jmpSkipClamp2Pos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
      patch8 jmpSkipClamp2Pos

      ff = genAllocTempMemory(OP_TYPE_REG, 8, 7)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      genBlockTransfer 6, 7, 8

      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 8)

    CASE TOK_RIGHT
      tasm_LoadOperand arg1$, 0, isFloat1
      tasm_LoadOperand arg2$, 8, isFloat2

      ff = genLoadStringDesc(0, 6, 1)

      ff = opALU(ALU_CMP, OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
      jmpSkipClamp1Pos = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opMov(OP_TYPE_REG, 8, OP_TYPE_REG, 1, 64)
      patch8 jmpSkipClamp1Pos

      ff = opTest(OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
      jmpSkipClamp2Pos = opJcc(JCC_JGE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
      ff = opALU(ALU_XOR, OP_TYPE_REG, 8, OP_TYPE_REG, 8, 64)
      patch8 jmpSkipClamp2Pos

      ff = opMov(OP_TYPE_REG, 2, OP_TYPE_REG, 1, 64)
      ff = opALU(ALU_SUB, OP_TYPE_REG, 2, OP_TYPE_REG, 8, 64)
      ff = opALU(ALU_ADD, OP_TYPE_REG, 6, OP_TYPE_REG, 2, 64)

      ff = genAllocTempMemory(OP_TYPE_REG, 8, 7)
      ff = opMov(OP_TYPE_REG, 14, OP_TYPE_REG, 7, 64)
      genBlockTransfer 6, 7, 8

      ff = genUpdateStringDescriptor(resolveSymbol(destVar$), 14, 8)

    CASE TOK_KEYDOWN
      tasm_LoadOperand arg1$, 1, isFloat1
      addPatch PATCH_RT, opCall(0, CALLMODE_REL32), RT_KEYDOWN, 0
      tasm_StoreOperand destVar$, 0, 0

  END SELECT

END SUB ' tasm_Intrinsic

''''''''''''''''''''''''
SUB tasm_LoadOperand (opStr$, destReg AS LONG, isFloat AS LONG)

  DIM firstChar AS STRING * 1
  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM opMode AS LONG

  firstChar = LEFT$(opStr$, 1)

  IF firstChar = "&" THEN
    vIdx = resolveSymbol(MID$(opStr$, 2))
    IF symbols(vIdx).IsArray = 2 THEN
      ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)
    ELSE
      ff = genSymbolRouteLea(destReg, vIdx)
    END IF
    isFloat = 0
    EXIT SUB
  END IF

  IF (firstChar >= "0" AND firstChar <= "9") OR firstChar = "-" OR firstChar = CHR$(34) THEN
    IF firstChar = CHR$(34) THEN
      lit$ = extractQuotes$(opStr$)
      vIdx = resolveSymbol("!LIT" + cTrNum$(tempVarCounter) + "$")
      tempVarCounter = tempVarCounter + 1
      IF vIdx <> -1 THEN strVarData$(vIdx) = lit$
      ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)
      isFloat = 0
    ELSE
      IF INSTR(opStr$, ".") > 0 THEN
        vIdx = resolveSymbol("!FLTLIT" + cTrNum$(tempVarCounter))
        tempVarCounter = tempVarCounter + 1
        IF vIdx <> -1 THEN
          symbols(vIdx).DataType = TYPE_DOUBLE
          floatVarData(vIdx) = VAL(opStr$)
          ff = genSymbolRouteSSE(SSE_MOV, OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, MODE_SSE_DOUBLE, vIdx)
        END IF
        isFloat = 2
      ELSE
        ff = opMov(OP_TYPE_REG, destReg, OP_TYPE_IMM, VAL(opStr$), MODE_IMM64)
        isFloat = 0
      END IF
    END IF
  ELSE
    vIdx = resolveSymbol(opStr$)
    dt = symbols(vIdx).DataType
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
          CASE ELSE: ff = genSymbolRouteMov(OP_TYPE_REG, destReg, OP_TYPE_MEM_RIP, 0, 64, vIdx)

        END SELECT ' dt

      END IF
      isFloat = 0
    END IF
  END IF

END SUB ' tasm_LoadOperand

''''''''''''''''''''''''
SUB tasm_SplitArgs (wArgs$, argsArray$(), argCount AS LONG)

  argCount = 0
  ix = 1
  aLen = LEN(wArgs$)
  currArg$ = ""

  DO WHILE ix <= aLen
    ch$ = MID$(wArgs$, ix, 1)
    IF ch$ = "," THEN
      argsArray$(argCount) = LTRIM$(RTRIM$(currArg$))
      argCount = argCount + 1
      currArg$ = ""
    ELSE
      currArg$ = currArg$ + ch$
    END IF
    ix = ix + 1
  LOOP

  IF currArg$ <> "" THEN
    argsArray$(argCount) = LTRIM$(RTRIM$(currArg$))
    argCount = argCount + 1
  END IF

END SUB ' tasm_SplitArgs

''''''''''''''''''''''''
SUB tasm_StoreOperand (opStr$, srcReg AS LONG, isFloat AS LONG)

  DIM vIdx AS LONG
  DIM targetType AS LONG
  DIM opMode AS LONG
  DIM isSingle AS LONG

  vIdx = resolveSymbol(opStr$)
  targetType = symbols(vIdx).DataType

  IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
    isSingle = 0
    IF targetType = TYPE_SINGLE THEN isSingle = 1

    IF isFloat = 0 THEN
      ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, srcReg, OP_TYPE_REG, srcReg, MODE_SSE_DOUBLE)
      isFloat = 2
    END IF

    IF isFloat = 2 AND isSingle = 1 THEN
      ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, srcReg, OP_TYPE_REG, srcReg, MODE_SSE_DOUBLE)
      isFloat = 1
    END IF
    IF isFloat = 1 AND isSingle = 0 THEN
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
      CASE ELSE
        ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, srcReg, 64, vIdx)

    END SELECT ' targetType

  END IF

END SUB ' tasm_StoreOperand

''''''''''''''''''''''''
SUB tiraAssign (dest$, src$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_ASSIGN
  tiraCode$(t.LineCount) = dest$ + ", " + src$
  t.LineCount = t.LineCount + 1

END SUB ' tiraAssign

''''''''''''''''''''''''
SUB tiraCall (funcName$, argCount AS LONG, argList$)

  ' tiraEndAndProcess automatically handles the Windows x64 ABI stack
  ' alignment and shadow space allocation for all TIRA_CALLs. It detects "IAT_"
  ' prefixes to know when to allocate the mandatory 32-byte shadow space for
  ' external Windows APIs, and strips it away for "RT_" and internal SUBs
  ' to keep the stack lean, while always ensuring strict 16-byte alignment.

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_CALL

  IF argCount > 0 THEN
    tiraCode$(t.LineCount) = funcName$ + ", " + LTRIM$(RTRIM$(STR$(argCount))) + ", " + argList$
  ELSE
    tiraCode$(t.LineCount) = funcName$ + ", 0"
  END IF

  t.LineCount = t.LineCount + 1

END SUB ' tiraCall

''''''''''''''''''''''''
FUNCTION tiraDimVar$ (baseName$, wDataType AS LONG)

  DIM tempName AS STRING
  DIM vIdx AS LONG
  DIM typePrefix AS STRING

  SELECT CASE wDataType

    CASE TYPE_STRING: typePrefix = "TSTR_"
    CASE TYPE_SINGLE: typePrefix = "TSNG_"
    CASE TYPE_DOUBLE: typePrefix = "TDBL_"
    CASE TYPE_BYTE: typePrefix = "TBYT_"
    CASE TYPE_UBYTE: typePrefix = "TUBY_"
    CASE TYPE_INTEGER: typePrefix = "TINT_"
    CASE TYPE_UINTEGER: typePrefix = "TUIN_"
    CASE TYPE_LONG: typePrefix = "TLNG_"
    CASE TYPE_ULONG: typePrefix = "TULN_"
    CASE TYPE_INTEGER64: typePrefix = "TI64_"
    CASE TYPE_UINT64: typePrefix = "TU64_"
    CASE ELSE: typePrefix = "TUNK_"

  END SELECT

  ' Creates a highly readable, SSA-safe ephemeral variable name strictly bound to its datatype
  tempName = "~" + typePrefix + baseName$ + "_" + LTRIM$(RTRIM$(STR$(t.TempCounter)))
  t.TempCounter = t.TempCounter + 1

  vIdx = resolveSymbol(tempName)
  symbols(vIdx).DataType = wDataType

  tiraDimVar$ = tempName

END FUNCTION ' tiraDimVar$

''''''''''''''''''''''''
FUNCTION tiraBuildAstNode$ (nodeIdx, allowImplicit)

  DIM leftVar AS STRING
  DIM rightVar AS STRING
  DIM opVal AS LONG
  DIM resVar AS STRING

  IF astNodes(nodeIdx).OpType = AST_LEAF THEN
    resVar = tiraParseFactor$(astNodes(nodeIdx).StartIdx, astNodes(nodeIdx).EndIdx, allowImplicit)
    tiraBuildAstNode$ = resVar
    EXIT FUNCTION
  END IF

  leftVar = tiraBuildAstNode$(astNodes(nodeIdx).LeftNode, allowImplicit)
  IF leftVar = "" THEN
    tiraBuildAstNode$ = ""
    EXIT FUNCTION
  END IF

  rightVar = tiraBuildAstNode$(astNodes(nodeIdx).RightNode, allowImplicit)
  IF rightVar = "" THEN
    tiraBuildAstNode$ = ""
    EXIT FUNCTION
  END IF

  opVal = astNodes(nodeIdx).OpType

  ' Register the virtual temp variable so the backend knows its exact data type
  resVar = tiraDimVar$("T", astNodes(nodeIdx).DataType)

  SELECT CASE opVal

    CASE AST_ADD: tiraOp TC_ADD, resVar, leftVar, rightVar
    CASE AST_SUB: tiraOp TC_SUB, resVar, leftVar, rightVar
    CASE AST_MUL: tiraOp TC_MUL, resVar, leftVar, rightVar
    CASE AST_DIV: tiraOp TC_DIV, resVar, leftVar, rightVar
    CASE AST_IDIV: tiraOp TC_IDIV, resVar, leftVar, rightVar
    CASE AST_AND: tiraOp TC_AND, resVar, leftVar, rightVar
    CASE AST_OR: tiraOp TC_OR, resVar, leftVar, rightVar
    CASE AST_POWER: tiraOp TC_POW, resVar, leftVar, rightVar
    CASE AST_CONCAT: tiraOp TC_CONCAT, resVar, leftVar, rightVar

  END SELECT ' opVal

  exprIs.DataType = astNodes(nodeIdx).DataType
  exprIs.IsTemp = 1

  tiraBuildAstNode$ = resVar

END FUNCTION ' tiraBuildAstNode$

''''''''''''''''''''''''
SUB tiraEndAndProcess

  DIM args$(16)
  DIM aCount AS LONG
  DIM vIdx AS LONG
  DIM isFloat1 AS LONG
  DIM isFloat2 AS LONG
  DIM isFloat3 AS LONG
  DIM opMode AS LONG
  DIM pushedDummy AS LONG
  DIM allocSize AS LONG
  DIM cmdNum AS LONG

  FOR ii = 0 TO t.LineCount - 1
    cmdNum = tiraCmd(ii)

    IF cmdNum = 0 THEN
      throwCompilerError "INVALID TIRA COMMAND (0)", ASIS, 0
      t.IsActive = 0
      EXIT SUB
    END IF

    argsStr$ = tiraCode$(ii)

    ' Clear array slot for next usage cycle to maintain a clean slate state
    tiraCmd(ii) = 0

    FOR iClear = 0 TO 15
      args$(iClear) = ""
    NEXT

    tasm_SplitArgs argsStr$, args$(), aCount

    IF cmdNum = TC_LABEL THEN
      labelName$ = argsStr$
      IF LEFT$(labelName$, 1) <> "&" THEN
        throwCompilerError "Internal labels must use & prefix", ASIS, 0
        t.IsActive = 0
        EXIT SUB
      END IF

      vIdx = resolveSymbol(labelName$)
      symbols(vIdx).DataType = TYPE_LABEL
      symbols(vIdx).Offset = emitPos
    ELSE

      SELECT CASE cmdNum

        CASE TC_ASSIGN
          tasm_LoadOperand args$(1), 0, isFloat1
          tasm_StoreOperand args$(0), 0, isFloat1

        CASE TC_ADD, TC_SUB, TC_MUL, TC_DIV, TC_IDIV, TC_AND, TC_OR, TC_POW, TC_CONCAT
          tasm_DoMath cmdNum, args$(0), args$(1), args$(2)

        CASE TC_SHL, TC_SHR
          tasm_DoShift cmdNum, args$(0), args$(1), args$(2)

        CASE TC_NEG, TC_NOT
          tasm_DoUnary cmdNum, args$(0), args$(1)

        CASE TC_JMP
          IF LEFT$(args$(0), 1) <> "&" THEN
            throwCompilerError "Internal jump targets must use & prefix", ASIS, 0
            t.IsActive = 0
            EXIT SUB
          END IF
          vIdx = resolveSymbol(args$(0))
          addPatch PATCH_GOTO, opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB

        CASE TC_JMP_USER
          vIdx = resolveSymbol(args$(0))
          addPatch PATCH_GOTO, opJcc(JCC_JMP, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB

        CASE TC_READ_MEM
          destStr$ = args$(0)
          ptrStr$ = args$(1)

          destVIdx = resolveSymbol(destStr$)
          targetType = symbols(destVIdx).DataType

          tasm_LoadOperand ptrStr$, 2, isFloat1

          IF targetType = TYPE_SINGLE OR targetType = TYPE_DOUBLE THEN
            IF targetType = TYPE_SINGLE THEN
              ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 32)
            ELSE
              ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 64)
            END IF
            ff = opSSE(SSE_MOVQ_XMM_REG, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
            isFloat1 = 2
          ELSE

            SELECT CASE targetType

              CASE TYPE_BYTE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVSX64_8)
              CASE TYPE_UBYTE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVZX64_8)
              CASE TYPE_INTEGER: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVSX64_16)
              CASE TYPE_UINTEGER: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVZX64_16)
              CASE TYPE_LONG: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, MODE_MOVSXD)
              CASE TYPE_ULONG, TYPE_SINGLE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 32)
              CASE ELSE: ff = opMov(OP_TYPE_REG, 0, OP_TYPE_MEM_REG, 2, 64)

            END SELECT ' targetType

            isFloat1 = 0
          END IF

          tasm_StoreOperand destStr$, 0, isFloat1

        CASE TC_FRAMEBUF_PTR
          destStr$ = args$(0)
          addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -3, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB
          tasm_StoreOperand destStr$, 0, 0

        CASE TC_WRITE_MEM
          destAddrStr$ = args$(0)
          srcValStr$ = args$(1)
          sizeMode$ = args$(2)

          tasm_LoadOperand destAddrStr$, 2, isFloat1
          tasm_LoadOperand srcValStr$, 0, isFloat2

          IF sizeMode$ = "SINGLE" OR sizeMode$ = "DOUBLE" THEN
            IF isFloat2 = 0 THEN
              ff = opSSE(SSE_CVTSI2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
              isFloat2 = 2
            END IF
            opMode = MODE_SSE_DOUBLE: IF sizeMode$ = "SINGLE" THEN opMode = MODE_SSE_SINGLE

            IF isFloat2 = 2 AND sizeMode$ = "SINGLE" THEN
              ff = opSSE(SSE_CVTSD2SS, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_DOUBLE)
            END IF
            IF isFloat2 = 1 AND sizeMode$ = "DOUBLE" THEN
              ff = opSSE(SSE_CVTSS2SD, OP_TYPE_REG, 0, OP_TYPE_REG, 0, MODE_SSE_SINGLE)
            END IF

            ff = opSSE(SSE_MOV, OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, opMode)
          ELSE
            IF isFloat2 > 0 THEN
              opMode = MODE_SSE_DOUBLE: IF isFloat2 = 1 THEN opMode = MODE_SSE_SINGLE
              ff = opSSE(SSE_CVTTSD2SI, OP_TYPE_REG, 0, OP_TYPE_REG, 0, opMode)
            END IF

            SELECT CASE sizeMode$
              CASE "1": ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 8)
              CASE "2": ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 16)
              CASE "4": ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 32)
              CASE "8": ff = opMov(OP_TYPE_MEM_REG, 2, OP_TYPE_REG, 0, 64)
            END SELECT
          END IF

        CASE TC_MEMCPY
          destAddrStr$ = args$(0)
          srcAddrStr$ = args$(1)
          lenStr$ = args$(2)

          tasm_LoadOperand destAddrStr$, 7, isFloat1 ' Load into RDI
          tasm_LoadOperand srcAddrStr$, 6, isFloat2 ' Load into RSI
          tasm_LoadOperand lenStr$, 1, isFloat3 ' Load into RCX

          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          jmpSkipMemCpy = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
          opFlag FLAG_CLD
          opString STR_MOVS, REP_REP, 8
          patch8 jmpSkipMemCpy

        CASE TC_MEMSET
          destAddrStr$ = args$(0)
          valStr$ = args$(1)
          lenStr$ = args$(2)

          tasm_LoadOperand destAddrStr$, 7, isFloat1 ' Load into RDI
          tasm_LoadOperand valStr$, 0, isFloat2 ' Load into RAX
          tasm_LoadOperand lenStr$, 1, isFloat3 ' Load into RCX

          ff = opTest(OP_TYPE_REG, 1, OP_TYPE_REG, 1, 64)
          jmpSkipMemSet = opJcc(JCC_JLE, JCC_MODE_FORWARD, 0, JCC_TYPE_SHORT)
          opFlag FLAG_CLD
          opString STR_STOS, REP_REP, 8
          patch8 jmpSkipMemSet

        CASE TC_JMP_COND
          condCodeStr$ = args$(0)
          src1Str$ = args$(1)
          src2Str$ = args$(2)
          targetLabel$ = args$(3)

          IF LEFT$(targetLabel$, 1) <> "&" THEN
            throwCompilerError "Internal jump targets must use & prefix", ASIS, 0
            t.IsActive = 0
            EXIT SUB
          END IF

          tasm_LoadOperand src1Str$, 0, isFloat1
          tasm_LoadOperand src2Str$, 3, isFloat2

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
              opModeFloat = MODE_SSE_DOUBLE: IF isFloat2 = 1 THEN opModeFloat = MODE_SSE_SINGLE
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
            END SELECT

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

          vIdx = resolveSymbol(targetLabel$)
          addPatch PATCH_GOTO, opJcc(jmpType, JCC_MODE_FORWARD, 0, JCC_TYPE_NEAR), vIdx, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB

        CASE TC_GET_RET
          destStr$ = args$(0)
          destIdx = resolveSymbol(destStr$)
          targetType = symbols(destIdx).DataType

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
              CASE ELSE
                ff = genSymbolRouteMov(OP_TYPE_MEM_RIP, 0, OP_TYPE_REG, 0, 64, destIdx)

            END SELECT ' targetType

          END IF

        CASE TC_REDRAW
          ' lea rax, [rip + HwndBase]
          addPatch PATCH_GFX, opLea(OP_TYPE_REG, 0, OP_TYPE_MEM_RIP, 0, 64), -4, 0
          IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB

          ' mov rcx, [rax]
          ff = opMov(OP_TYPE_REG, 1, OP_TYPE_MEM_REG, 0, 64)

          ' xor edx, edx
          ff = opALU(ALU_XOR, OP_TYPE_REG, 2, OP_TYPE_REG, 2, 32)

          ' mov r8d, 1 (bErase = TRUE, forces the background to clear so old dots don't trail)
          ff = opMov(OP_TYPE_REG, 8, OP_TYPE_IMM, 1, 32)

          ff = genAlignedCall(IAT_INVALIDATERECT, 13, DEFAULT)

        CASE TC_CALL
          funcName$ = args$(0)
          argCount = VAL(args$(1))

          IF argCount > 16 THEN
            throwCompilerError "TIRA_CALL WITH > 16 ARGS NOT SUPPORTED", ASIS, 0
            t.IsActive = 0
            EXIT SUB
          END IF

          DIM isIAT AS LONG
          DIM isRT AS LONG
          isIAT = 0
          isRT = 0
          IF LEFT$(funcName$, 4) = "IAT_" THEN isIAT = 1
          IF LEFT$(funcName$, 3) = "RT_" THEN isRT = 1

          allocSize = 0

          IF isIAT = 1 THEN
            allocSize = 32
            IF argCount > 4 THEN
              allocSize = allocSize + ((argCount - 4) * 8)
            END IF
          ELSE
            ' Internal calls don't need the 32-byte shadow space overhead
            IF argCount > 4 THEN
              allocSize = (argCount - 4) * 8
            END IF
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
            opSubRsp32 allocSize
          END IF

          ' Standard Win64 Calling Convention Routing Loop
          FOR iArg = 0 TO argCount - 1
            ' First load the operand into RAX or XMM0 blindly
            tasm_LoadOperand args$(2 + iArg), 0, isFloat1

            IF isFloat1 > 0 THEN
              ' Route to standard XMM register block or Stack
              opMode = MODE_SSE_DOUBLE: IF isFloat1 = 1 THEN opMode = MODE_SSE_SINGLE

              SELECT CASE iArg

                CASE 0
                  ' already in xmm0
                CASE 1
                  ff = opSSE(SSE_MOV, OP_TYPE_REG, 1, OP_TYPE_REG, 0, opMode)
                CASE 2
                  ff = opSSE(SSE_MOV, OP_TYPE_REG, 8, OP_TYPE_REG, 0, opMode)
                CASE 3
                  ff = opSSE(SSE_MOV, OP_TYPE_REG, 9, OP_TYPE_REG, 0, opMode)
                CASE ELSE
                  IF isIAT = 1 THEN
                    ff = opSSE(SSE_MOV, OP_TYPE_MEM_RSP, 32 + ((iArg - 4) * 8), OP_TYPE_REG, 0, opMode)
                  ELSE
                    ff = opSSE(SSE_MOV, OP_TYPE_MEM_RSP, (iArg - 4) * 8, OP_TYPE_REG, 0, opMode)
                  END IF

              END SELECT ' iArg

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
                  IF isIAT = 1 THEN
                    ff = opMov(OP_TYPE_MEM_RSP, 32 + ((iArg - 4) * 8), OP_TYPE_REG, 0, 64)
                  ELSE
                    ff = opMov(OP_TYPE_MEM_RSP, (iArg - 4) * 8, OP_TYPE_REG, 0, 64)
                  END IF

              END SELECT ' iArg

            END IF
          NEXT

          ' Resolve Subroutine offset dynamically
          IF isRT = 1 THEN
            DIM rtOffset AS LONG
            rtOffset = 0

            SELECT CASE funcName$

              CASE "RT_KEYDOWN": rtOffset = RT_KEYDOWN
              CASE "RT_LINE": rtOffset = RT_LINE
              CASE "RT_PLOT_PIXEL": rtOffset = RT_PLOT_PIXEL
              CASE "RT_STR_ASSIGN": rtOffset = RT_STR_ASSIGN
              CASE "RT_VEH_HANDLER": rtOffset = RT_VEH_HANDLER

            END SELECT ' funcName$

            IF rtOffset = 0 THEN
              throwCompilerError "RUNTIME HELPER NOT FOUND IN TIRA_CALL: " + funcName$, ASIS, 0
              t.IsActive = 0
              EXIT SUB
            END IF

            addPatch PATCH_RT, opCall(0, CALLMODE_REL32), rtOffset, 0
            IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB

          ELSE
            IF isIAT = 1 THEN
              DIM iatConst AS LONG
              iatConst = IAT_INVALID

              SELECT CASE funcName$

                CASE "IAT_BEEP": iatConst = IAT_BEEP
                CASE "IAT_SLEEP": iatConst = IAT_SLEEP
                CASE "IAT_ATAN": iatConst = IAT_ATAN
                CASE "IAT_GETASYNCKEYSTATE": iatConst = IAT_GETASYNCKEYSTATE
                CASE "IAT_GETSTDHANDLE": iatConst = IAT_GETSTDHANDLE
                CASE "IAT_SETCONSOLECURSORPOSITION": iatConst = IAT_SETCONSOLECURSORPOSITION
                CASE "IAT_WRITEFILE": iatConst = IAT_WRITEFILE
                CASE "IAT_SETCONSOLETEXTATTRIBUTE": iatConst = IAT_SETCONSOLETEXTATTRIBUTE
                CASE "IAT_INVALIDATERECT": iatConst = IAT_INVALIDATERECT

              END SELECT ' funcName$

              IF iatConst = IAT_INVALID THEN
                throwCompilerError "INVALID IAT CALL: " + funcName$, ASIS, 0
                t.IsActive = 0
                EXIT SUB
              END IF

              ' Directly run an unprotected opCall because TIRA_CALL intrinsically guarantees stack alignments now
              ff = opCall(iatConst, CALLMODE_IAT)
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB

            ELSE
              ' User SUB mapping
              addPatchStr PATCH_CALL, opCall(0, CALLMODE_REL32), funcName$
              IF LEFT$(compileStatusMsg$, 5) = "ERROR" THEN t.IsActive = 0: EXIT SUB
            END IF
          END IF

          ' Restore stack footprint offsets safely
          IF allocSize > 0 THEN
            opAddRsp32 allocSize
          END IF
          IF pushedDummy = 1 THEN
            opPopReg 13
          END IF

        CASE TC_INTRINSIC
          tasm_Intrinsic VAL(args$(0)), args$(1), args$(2), args$(3), args$(4)

        CASE ELSE
          throwCompilerError "TIRA COMMAND NOT IMPLEMENTED IN BACKEND", ASIS, 0
          t.IsActive = 0
          EXIT SUB

      END SELECT ' cmdNum

    END IF
  NEXT

  t.LineCount = 0 ' Reset for another TIRA round, triggered by tira Start function
  t.IsActive = 0

END SUB ' tiraEndAndProcess

''''''''''''''''''''''''
FUNCTION tiraFindComma (startIdx, endIdx)

  DIM commaPos AS LONG
  commaPos = 0

  FOR ii = startIdx TO endIdx
    IF retTokenVal(lineTokens$(ii)) = 256 + ASC(",") THEN
      commaPos = ii
      EXIT FOR
    END IF
  NEXT

  IF commaPos > 0 THEN
    tiraFindComma = 1
    return2 commaPos
  ELSE
    tiraFindComma = 0
    return2 0 ' Just in case it hasn't been reset
  END IF

END FUNCTION ' tiraFindComma

''''''''''''''''''''''''
FUNCTION tiraForceInt$ (srcVar$)

  DIM vIdx AS LONG
  DIM dt AS LONG
  DIM resVar AS STRING

  vIdx = resolveSymbol(srcVar$)
  dt = symbols(vIdx).DataType

  ' If the virtual register holds a float, we must create a new integer temp
  ' register and assign it to force a TIRA conversion in the backend.
  IF dt = TYPE_SINGLE OR dt = TYPE_DOUBLE THEN
    resVar = tiraDimVar$("T", TYPE_LONG)
    tiraAssign resVar, srcVar$
    tiraForceInt$ = resVar
  ELSE
    tiraForceInt$ = srcVar$
  END IF

END FUNCTION ' tiraForceInt$

''''''''''''''''''''''''
FUNCTION tiraFrontendCalcAddress$ (vName$, xVar$, yVar$, udtOffset AS LONG)

  DIM baseAddrVar AS STRING
  DIM vIdx AS LONG
  DIM offsetVar AS STRING
  DIM axVar AS STRING
  DIM yOffset AS STRING
  DIM combinedOffset AS STRING
  DIM elemSize AS LONG
  DIM dt AS LONG
  DIM byteOffset AS STRING
  DIM finalAddr AS STRING
  DIM newAddr AS STRING
  DIM lenIdx AS LONG

  vIdx = resolveSymbol(vName$)

  baseAddrVar$ = tiraDimVar$("T", TYPE_INTEGER64)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    tiraFrontendCalcAddress$ = ""
    EXIT FUNCTION
  END IF

  tiraAssign baseAddrVar$, "&" + vName$

  offsetVar$ = ""
  IF xVar$ <> "" THEN
    offsetVar$ = xVar$
    IF yVar$ <> "" THEN
      axVar$ = "!" + vName$ + "_AX"
      yOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_MUL, yOffset$, yVar$, axVar$
      combinedOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_ADD, combinedOffset$, offsetVar$, yOffset$
      offsetVar$ = combinedOffset$
    END IF

    dt = symbols(vIdx).DataType
    elemSize = 8

    SELECT CASE dt

      CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
      CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
      CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
      CASE TYPE_STRING
        lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
        IF floatVarData(lenIdx) > 0 THEN
          elemSize = floatVarData(lenIdx)
        ELSE
          elemSize = 8
        END IF
      CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize

    END SELECT ' dt

    IF elemSize <> 1 THEN
      byteOffset$ = tiraDimVar$("T", TYPE_INTEGER64)
      tiraOp TC_MUL, byteOffset$, offsetVar$, LTRIM$(RTRIM$(STR$(elemSize)))
      offsetVar$ = byteOffset$
    END IF
  END IF

  finalAddr$ = baseAddrVar$
  IF offsetVar$ <> "" THEN
    newAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, newAddr$, finalAddr$, offsetVar$
    finalAddr$ = newAddr$
  END IF

  IF udtOffset > 0 THEN
    newAddr$ = tiraDimVar$("T", TYPE_INTEGER64)
    tiraOp TC_ADD, newAddr$, finalAddr$, LTRIM$(RTRIM$(STR$(udtOffset)))
    finalAddr$ = newAddr$
  END IF

  tiraFrontendCalcAddress$ = finalAddr$

END FUNCTION ' tiraFrontendCalcAddress$

''''''''''''''''''''''''
SUB tiraJmp (labelName$)

  IF LEFT$(labelName$, 1) <> "&" THEN
    throwCompilerError "Internal jump targets must use & prefix", ASIS, 0
    EXIT SUB
  END IF

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_JMP
  tiraCode$(t.LineCount) = labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraJmp

''''''''''''''''''''''''
SUB tiraJmpCond (cond$, src1$, src2$, labelName$)

  IF LEFT$(labelName$, 1) <> "&" THEN
    throwCompilerError "Internal jump targets must use & prefix", ASIS, 0
    EXIT SUB
  END IF

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_JMP_COND
  tiraCode$(t.LineCount) = cond$ + ", " + src1$ + ", " + src2$ + ", " + labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraJmpCond

''''''''''''''''''''''''
SUB tiraLabel (labelName$)

  IF LEFT$(labelName$, 1) <> "&" THEN
    throwCompilerError "Internal labels must use & prefix", ASIS, 0
    EXIT SUB
  END IF

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_LABEL
  tiraCode$(t.LineCount) = labelName$
  t.LineCount = t.LineCount + 1

END SUB ' tiraLabel
''''''''''''''''''''''''

FUNCTION tiraLabelNew$ (baseName$)

  DIM tempName AS STRING

  ' Creates a unique jump label globally unique across the file (e.g., &loopLbl_5)
  tempName = "&" + baseName$ + "_" + LTRIM$(RTRIM$(STR$(tempVarCounter)))
  tempVarCounter = tempVarCounter + 1

  tiraLabelNew$ = tempName

END FUNCTION ' tiraLabelNew$

''''''''''''''''''''''''
SUB tiraMemcpy (destAddr$, srcAddr$, lenVal$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_MEMCPY
  tiraCode$(t.LineCount) = destAddr$ + ", " + srcAddr$ + ", " + lenVal$
  t.LineCount = t.LineCount + 1

END SUB ' tiraMemcpy

''''''''''''''''''''''''
SUB tiraMemSet (destAddr$, valStr$, lenVal$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_MEMSET
  tiraCode$(t.LineCount) = destAddr$ + ", " + valStr$ + ", " + lenVal$
  t.LineCount = t.LineCount + 1

END SUB ' tiraMemSet

''''''''''''''''''''''''
SUB tiraNew (opConst AS LONG, argsStr$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA QUEUE OVERFLOW", ASIS, 0
    EXIT SUB
  END IF

  IF opConst = 0 OR opConst >= TC_OUTOFRANGE THEN
    throwCompilerError "INVALID TC_", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = opConst
  tiraCode$(t.LineCount) = argsStr$

  t.LineCount = t.LineCount + 1

END SUB ' tiraNew

''''''''''''''''''''''''
FUNCTION tiraParseExpression$ (startIdx, endIdx, allowImplicit)

  ' tiraParseExpression$ relies completely on the calling function to handle tiraStart and tiraEndAndProcess

  DIM rootNode AS LONG
  DIM savedAstNodeCount AS LONG
  DIM resVar AS STRING

  ' Use the existing AST builder (it only generates tree nodes, no ABI logic)
  savedAstNodeCount = astNodeCount
  rootNode = buildAstExpression(startIdx, endIdx)

  IF rootNode = -1 THEN
    astNodeCount = savedAstNodeCount
    tiraParseExpression$ = ""
    EXIT FUNCTION
  END IF

  ' Traverse the tree to generate TIRA strings instead of x64 instructions
  resVar = tiraBuildAstNode$(rootNode, allowImplicit)

  astNodeCount = savedAstNodeCount
  tiraParseExpression$ = resVar

END FUNCTION ' tiraParseExpression$

''''''''''''''''''''''''
FUNCTION tiraParseFactor$ (startIdx, endIdx, allowImplicit)

  DIM resVar AS STRING
  DIM tVal AS LONG
  DIM vIdx AS LONG
  DIM exprRes AS LONG
  DIM targetType AS LONG
  DIM opMode AS LONG

  ' 1. INKEYF / INKEY
  IF startIdx = endIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx))
    IF tVal = TOK_INKEYF OR tVal = TOK_INKEY THEN
      resVar = tiraDimVar$("T", TYPE_STRING)
      tiraNew TC_INTRINSIC, cTrNum$(tVal) + ", " + resVar
      exprIs.DataType = TYPE_STRING
      exprIs.IsTemp = 1
      tiraParseFactor$ = resVar
      EXIT FUNCTION
    END IF
  END IF

  ' 2. LITERALS
  IF startIdx = endIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx))
    IF tVal = 0 THEN
      firstChar$ = LEFT$(lineTokens$(startIdx), 1)
      IF firstChar$ = CHR$(34) THEN
        ' String literal
        lit$ = extractQuotes$(lineTokens$(startIdx))
        vIdx = resolveSymbol("!LIT" + cTrNum$(tempVarCounter) + "$")
        tempVarCounter = tempVarCounter + 1
        IF vIdx <> -1 THEN strVarData$(vIdx) = lit$
        exprIs.DataType = TYPE_STRING
        exprIs.IsTemp = 0
        tiraParseFactor$ = RTRIM$(symbols(vIdx).RecordName)
        EXIT FUNCTION
      ELSE
        IF (firstChar$ >= "0" AND firstChar$ <= "9") OR firstChar$ = "-" THEN
          ' Number literal
          IF INSTR(lineTokens$(startIdx), ".") > 0 THEN
            exprIs.DataType = TYPE_DOUBLE
          ELSE
            exprIs.DataType = TYPE_LONG
          END IF
          exprIs.IsTemp = 0
          tiraParseFactor$ = lineTokens$(startIdx)
          EXIT FUNCTION
        END IF
      END IF
    END IF
  END IF

  ' 3. UNARY
  IF startIdx < endIdx THEN
    tVal = retTokenVal(lineTokens$(startIdx))
    IF tVal = 256 + ASC("-") OR tVal = TOK_NOT THEN
      innerVar$ = tiraParseFactor$(startIdx + 1, endIdx, allowImplicit)
      IF innerVar$ = "" THEN
        tiraParseFactor$ = ""
        EXIT FUNCTION
      END IF

      resVar = tiraDimVar$("T", exprIs.DataType)

      IF tVal = 256 + ASC("-") THEN
        tiraNew TC_NEG, resVar + ", " + innerVar$
      ELSE
        tiraNew TC_NOT, resVar + ", " + innerVar$
      END IF
      tiraParseFactor$ = resVar
      EXIT FUNCTION
    END IF
  END IF

  ' 4. PARENTHESES
  IF retTokenVal(lineTokens$(startIdx)) = 256 + ASC("(") THEN
    IF findMatchingParen(startIdx, endIdx) = endIdx THEN
      tiraParseFactor$ = tiraParseExpression$(startIdx + 1, endIdx - 1, allowImplicit)
      EXIT FUNCTION
    END IF
  END IF

  ' 5. INTRINSICS
  tVal = retTokenVal(lineTokens$(startIdx))
  isIntrinsic = 0
  FOR ii = 0 TO intrinsicCount - 1
    IF tVal = intrinsicDefs(ii).TokenVal THEN
      isIntrinsic = 1
      EXIT FOR
    END IF
  NEXT

  IF isIntrinsic = 1 THEN
    resVar = tiraParseIntrinsic$(startIdx, endIdx, allowImplicit)
    IF resVar = "" THEN
      tiraParseFactor$ = ""
      EXIT FUNCTION
    END IF
    tiraParseFactor$ = resVar
    EXIT FUNCTION
  END IF

  ' 6. IDENTIFIERS (Variables, Arrays, UDTs, Function Calls)
  vTok$ = lineTokens$(startIdx)
  IF retTokenVal(vTok$) = 0 AND LEN(vTok$) > 0 THEN
    firstChar$ = LEFT$(vTok$, 1)
    IF (firstChar$ >= "A" AND firstChar$ <= "Z") OR (firstChar$ >= "a" AND firstChar$ <= "z") OR firstChar$ = "!" THEN

      vName$ = UCASE$(vTok$)
      hasIndex = 0
      closeParenIdx = -1
      tokIdx = startIdx + 1

      IF tokIdx <= endIdx THEN
        IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC("(") THEN
          hasIndex = 1
          closeParenIdx = findMatchingParen(tokIdx, endIdx)
          IF closeParenIdx = -1 THEN
            throwCompilerError "MISSING )", ASIS, 0
            tiraParseFactor$ = "": EXIT FUNCTION
          END IF
          tokIdx = closeParenIdx + 1
        END IF
      END IF

      hasField = 0
      IF tokIdx <= endIdx THEN
        IF retTokenVal(lineTokens$(tokIdx)) = 256 + ASC(".") THEN hasField = 1
      END IF

      IF hasIndex = 1 OR hasField = 1 THEN expectedSymType = TYPE_ANY

      vIdx = findSymbol(vName$)
      IF vIdx = -1 THEN
        IF allowImplicit = 0 THEN
          throwCompilerError "UNDECLARED VARIABLE OR FUNCTION '" + vName$ + "'", ASIS, 0
          tiraParseFactor$ = ""
          EXIT FUNCTION
        ELSE
          vIdx = resolveSymbol(vName$)
          IF vIdx = -1 THEN tiraParseFactor$ = "": EXIT FUNCTION
        END IF
      END IF

      subIdx = symbols(vIdx).SubIndex

      ' FUNCTION CALL
      IF subIdx <> -1 THEN
        IF tokIdx <= endIdx THEN
          throwCompilerError "UNEXPECTED TOKENS AFTER FUNCTION", ASIS, 0
          tiraParseFactor$ = "": EXIT FUNCTION
        END IF

        argIdx = 0
        IF hasIndex = 1 AND closeParenIdx > startIdx + 2 THEN
          aStart = startIdx + 2
          DO WHILE aStart < closeParenIdx
            aEnd = findNextTokenAtDepth0(aStart, closeParenIdx - 1, 256 + ASC(","))
            IF aEnd = -1 THEN aEnd = closeParenIdx

            IF argIdx >= subs(subIdx).ArgCount THEN
              throwCompilerError "TOO MANY ARGS FOR " + vName$, ASIS, 0
              tiraParseFactor$ = "": EXIT FUNCTION
            END IF

            argVar$ = tiraParseExpression$(aStart, aEnd - 1, allowImplicit)
            IF argVar$ = "" THEN tiraParseFactor$ = "": EXIT FUNCTION

            targetVarIdx = subArgVarIdx(subIdx, argIdx)

            ' Type checking
            IF symbols(targetVarIdx).IsArray = 2 THEN
              IF exprIs.DataType = TYPE_STRING AND symbols(targetVarIdx).DataType <> TYPE_STRING THEN
                throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
                tiraParseFactor$ = "": EXIT FUNCTION
              END IF
              IF exprIs.DataType <> TYPE_STRING AND symbols(targetVarIdx).DataType = TYPE_STRING THEN
                throwCompilerError "TYPE MISMATCH ARG " + LTRIM$(STR$(argIdx + 1)), ASIS, 0
                tiraParseFactor$ = "": EXIT FUNCTION
              END IF
            ELSE
              IF symbols(targetVarIdx).DataType = TYPE_STRING THEN
                IF exprIs.DataType <> TYPE_STRING THEN
                  throwCompilerError "TYPE MISMATCH ARG", ASIS, 0
                  tiraParseFactor$ = "": EXIT FUNCTION
                END IF
              ELSE
                IF exprIs.DataType = TYPE_STRING THEN
                  throwCompilerError "TYPE MISMATCH ARG", ASIS, 0
                  tiraParseFactor$ = "": EXIT FUNCTION
                END IF
              END IF
            END IF

            targetVarName$ = RTRIM$(symbols(targetVarIdx).RecordName)
            IF symbols(targetVarIdx).IsArray = 2 THEN
              tiraAssign targetVarName$, argVar$
            ELSE
              IF symbols(targetVarIdx).DataType = TYPE_STRING THEN
                tiraCall "RT_STR_ASSIGN", 2, "&" + targetVarName$ + ", " + argVar$
              ELSE
                tiraAssign targetVarName$, argVar$
              END IF
            END IF

            argIdx = argIdx + 1
            aStart = aEnd + 1
          LOOP
        END IF

        IF argIdx < subs(subIdx).ArgCount THEN
          throwCompilerError "TOO FEW ARGS FOR " + vName$, ASIS, 0
          tiraParseFactor$ = "": EXIT FUNCTION
        END IF

        ' Call User SUB passing zero ABI stack arguments
        tiraCall vName$, 0, ""

        exprIs.IsTemp = 0
        IF subs(subIdx).IsFunction = 1 THEN
          retVarIdx = subs(subIdx).ReturnVarIdx
          exprIs.DataType = symbols(retVarIdx).DataType
          resVar = tiraDimVar$("T", exprIs.DataType)
          tiraAssign resVar, vName$
        ELSE
          exprIs.DataType = TYPE_LONG
          resVar = tiraDimVar$("T", TYPE_LONG)
          tiraAssign resVar, "0" ' Dummy assignment
        END IF

        tiraParseFactor$ = resVar
        EXIT FUNCTION
      END IF

      ' VARIABLES, ARRAYS, UDTs
      IF vIdx <> -1 THEN
        udtOffset = 0
        targetType = symbols(vIdx).DataType

        IF hasField = 1 THEN
          tokIdx = tokIdx + 1
          IF tokIdx > endIdx THEN
            throwCompilerError "EXPECTED FIELD NAME", ASIS, 0
            tiraParseFactor$ = "": EXIT FUNCTION
          END IF
          fieldName$ = UCASE$(lineTokens$(tokIdx))
          tokIdx = tokIdx + 1

          IF symbols(vIdx).DataType <> TYPE_UDT THEN
            throwCompilerError "VARIABLE IS NOT A UDT", ASIS, 0
            tiraParseFactor$ = "": EXIT FUNCTION
          END IF

          uIdx = symbols(vIdx).UDTIndex
          fFound = 0
          FOR f = 0 TO udts(uIdx).FieldCount - 1
            IF RTRIM$(udtFields(uIdx, f).FieldName) = fieldName$ THEN
              udtOffset = udtFields(uIdx, f).Offset
              targetType = udtFields(uIdx, f).DataType
              fFound = 1
              EXIT FOR
            END IF
          NEXT
          IF fFound = 0 THEN
            throwCompilerError "UDT FIELD NOT FOUND", ASIS, 0
            tiraParseFactor$ = "": EXIT FUNCTION
          END IF
        END IF

        IF tokIdx <= endIdx THEN
          throwCompilerError "MALFORMED FACTOR", ASIS, 0
          tiraParseFactor$ = "": EXIT FUNCTION
        END IF

        xVar$ = ""
        yVar$ = ""

        IF hasIndex = 1 THEN
          commaIdx = findNextTokenAtDepth0(startIdx + 2, closeParenIdx - 1, 256 + ASC(","))

          IF commaIdx = -1 THEN
            IF startIdx + 2 = closeParenIdx THEN
              ' Array root pointer
              resVar = tiraDimVar$("T", targetType)
              tiraAssign resVar, RTRIM$(symbols(vIdx).RecordName)
              exprIs.DataType = targetType
              exprIs.IsTemp = 0
              tiraParseFactor$ = resVar
              EXIT FUNCTION
            END IF

            IF symbols(vIdx).Size2 > 0 AND symbols(vIdx).IsArray <> 2 THEN
              throwCompilerError "EXPECTED 2D ARRAY", ASIS, 0
              tiraParseFactor$ = "": EXIT FUNCTION
            END IF

            xVar$ = tiraParseExpression$(startIdx + 2, closeParenIdx - 1, allowImplicit)
            IF xVar$ = "" THEN tiraParseFactor$ = "": EXIT FUNCTION

            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "ARRAY INDEX MUST BE NUMERIC", ASIS, 0
              tiraParseFactor$ = "": EXIT FUNCTION
            END IF
          ELSE
            IF symbols(vIdx).Size2 = 0 AND symbols(vIdx).IsArray <> 2 THEN
              throwCompilerError "EXPECTED 1D ARRAY", ASIS, 0
              tiraParseFactor$ = "": EXIT FUNCTION
            END IF

            xVar$ = tiraParseExpression$(startIdx + 2, commaIdx - 1, allowImplicit)
            IF xVar$ = "" THEN tiraParseFactor$ = "": EXIT FUNCTION

            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "ARRAY INDEX MUST BE NUMERIC", ASIS, 0
              tiraParseFactor$ = "": EXIT FUNCTION
            END IF

            yVar$ = tiraParseExpression$(commaIdx + 1, closeParenIdx - 1, allowImplicit)
            IF yVar$ = "" THEN tiraParseFactor$ = "": EXIT FUNCTION

            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "ARRAY INDEX MUST BE NUMERIC", ASIS, 0
              tiraParseFactor$ = "": EXIT FUNCTION
            END IF
          END IF
        END IF

        resVar = tiraDimVar$("T", targetType)

        IF xVar$ = "" AND yVar$ = "" AND udtOffset = 0 THEN
          tiraAssign resVar, RTRIM$(symbols(vIdx).RecordName)
        ELSE
          finalAddr$ = tiraFrontendCalcAddress$(RTRIM$(symbols(vIdx).RecordName), xVar$, yVar$, udtOffset)
          IF finalAddr$ = "" THEN tiraParseFactor$ = "": EXIT FUNCTION
          tiraNew TC_READ_MEM, resVar + ", " + finalAddr$
        END IF

        exprIs.DataType = targetType
        exprIs.IsTemp = 0
        tiraParseFactor$ = resVar
        EXIT FUNCTION
      END IF
    END IF
  END IF

  throwCompilerError "MALFORMED EXPRESSION", ASIS, 0
  tiraParseFactor$ = ""

END FUNCTION ' tiraParseFactor$

''''''''''''''''''''''''
FUNCTION tiraParseIntrinsic$ (startIdx, endIdx, allowImplicit)

  DIM resVar AS STRING
  DIM arg1 AS STRING, arg2 AS STRING, arg3 AS STRING
  DIM isVariableLen AS LONG
  DIM reqSize AS LONG

  tVal = retTokenVal(lineTokens$(startIdx))
  resVar = ""

  SELECT CASE tVal

    CASE TOK_STR, TOK_VAL, TOK_LTRIM, TOK_RTRIM, TOK_UCASE, TOK_ASC, TOK_INT, TOK_ATN, TOK_CHR, TOK_KEYDOWN
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN

          IF tVal = TOK_STR OR tVal = TOK_CHR OR tVal = TOK_KEYDOWN THEN
            IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
          ELSE
            IF tVal = TOK_VAL OR tVal = TOK_LTRIM OR tVal = TOK_RTRIM OR tVal = TOK_UCASE OR tVal = TOK_ASC THEN
              IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
            ELSE
              IF tVal = TOK_INT OR tVal = TOK_ATN THEN
                IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              END IF
            END IF
          END IF

          arg1 = tiraParseExpression$(startIdx + 2, endIdx - 1, allowImplicit)
          IF arg1 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION

          IF tVal = TOK_STR OR tVal = TOK_CHR OR tVal = TOK_KEYDOWN OR tVal = TOK_INT OR tVal = TOK_ATN THEN
            IF exprIs.DataType = TYPE_STRING THEN
              throwCompilerError "INTRINSIC REQUIRES NUMERIC", ASIS, 0
              tiraParseIntrinsic$ = "": EXIT FUNCTION
            END IF
            IF tVal <> TOK_INT AND tVal <> TOK_ATN THEN
              arg1 = tiraForceInt$(arg1)
            END IF
          END IF

          IF tVal = TOK_VAL OR tVal = TOK_LTRIM OR tVal = TOK_RTRIM OR tVal = TOK_UCASE OR tVal = TOK_ASC THEN
            IF exprIs.DataType <> TYPE_STRING THEN
              throwCompilerError "INTRINSIC REQUIRES STRING", ASIS, 0
              tiraParseIntrinsic$ = "": EXIT FUNCTION
            END IF
          END IF

          SELECT CASE tVal

            CASE TOK_STR, TOK_LTRIM, TOK_RTRIM, TOK_UCASE, TOK_CHR
              resVar = tiraDimVar$("T", TYPE_STRING)
              exprIs.DataType = TYPE_STRING
            CASE TOK_VAL, TOK_ASC, TOK_INT, TOK_KEYDOWN
              resVar = tiraDimVar$("T", TYPE_LONG)
              exprIs.DataType = TYPE_LONG
            CASE TOK_ATN
              resVar = tiraDimVar$("T", TYPE_DOUBLE)
              exprIs.DataType = TYPE_DOUBLE

          END SELECT ' tVal

          tiraNew TC_INTRINSIC, cTrNum$(tVal) + ", " + resVar + ", " + arg1
          exprIs.IsTemp = 1
          tiraParseIntrinsic$ = resVar
          EXIT FUNCTION
        END IF
      END IF
      throwCompilerError "MALFORMED INTRINSIC", ASIS, 0

    CASE TOK_LEN
      IF startIdx + 3 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          innerStart = startIdx + 2
          innerEnd = endIdx - 1
          isVariableLen = 0
          reqSize = -1

          firstTok$ = lineTokens$(innerStart)
          IF retTokenVal(firstTok$) = 0 THEN
            firstChar$ = LEFT$(firstTok$, 1)
            IF (firstChar$ >= "A" AND firstChar$ <= "Z") OR (firstChar$ >= "a" AND firstChar$ <= "z") OR firstChar$ = "_" THEN
              vName$ = UCASE$(firstTok$)
              vIdx = findSymbol(vName$)
              IF vIdx <> -1 THEN
                isMatch = 0
                isArrayWhole = 0

                IF innerStart = innerEnd THEN
                  isMatch = 1
                ELSE
                  IF innerStart + 2 = innerEnd THEN
                    IF retTokenVal(lineTokens$(innerStart + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(innerEnd)) = 256 + ASC(")") THEN
                      isMatch = 1
                      isArrayWhole = 1
                    END IF
                  ELSE
                    IF retTokenVal(lineTokens$(innerStart + 1)) = 256 + ASC("(") THEN
                      IF findMatchingParen(innerStart + 1, innerEnd) = innerEnd THEN
                        isMatch = 1
                      END IF
                    END IF
                  END IF
                END IF

                IF isMatch = 1 THEN
                  dt = symbols(vIdx).DataType
                  elemSize = 0

                  SELECT CASE dt

                    CASE TYPE_BYTE, TYPE_UBYTE: elemSize = 1
                    CASE TYPE_INTEGER, TYPE_UINTEGER: elemSize = 2
                    CASE TYPE_LONG, TYPE_ULONG, TYPE_SINGLE: elemSize = 4
                    CASE TYPE_INTEGER64, TYPE_UINT64, TYPE_DOUBLE: elemSize = 8
                    CASE TYPE_UDT: elemSize = udts(symbols(vIdx).UDTIndex).TotalSize
                    CASE TYPE_STRING:
                      lenIdx = resolveSymbol("!LEN_" + RTRIM$(symbols(vIdx).RecordName))
                      IF floatVarData(lenIdx) > 0 THEN
                        elemSize = floatVarData(lenIdx)
                      ELSE
                        elemSize = -1
                      END IF

                  END SELECT ' dt

                  IF isArrayWhole = 1 THEN
                    IF symbols(vIdx).IsArray = 0 THEN
                      throwCompilerError "EXPECTED ARRAY", ASIS, 0
                      tiraParseIntrinsic$ = "": EXIT FUNCTION
                    END IF
                    IF elemSize = -1 THEN
                      throwCompilerError "CANNOT USE LEN ON DYNAMIC STRING ARRAY", ASIS, 0
                      tiraParseIntrinsic$ = "": EXIT FUNCTION
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

          IF isVariableLen = 1 THEN
            resVar = tiraDimVar$("T", TYPE_LONG)
            tiraAssign resVar, LTRIM$(STR$(reqSize))
            exprIs.DataType = TYPE_LONG
            exprIs.IsTemp = 1
            tiraParseIntrinsic$ = resVar
            EXIT FUNCTION
          END IF

          IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
          arg1 = tiraParseExpression$(innerStart, innerEnd, allowImplicit)
          IF arg1 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
          IF exprIs.DataType <> TYPE_STRING THEN
            throwCompilerError "VARIABLE REQUIRED FOR NUMERIC LEN", ASIS, 0
            tiraParseIntrinsic$ = "": EXIT FUNCTION
          END IF

          resVar = tiraDimVar$("T", TYPE_LONG)
          tiraNew TC_INTRINSIC, cTrNum$(TOK_LEN) + ", " + resVar + ", " + arg1
          exprIs.DataType = TYPE_LONG
          exprIs.IsTemp = 1
          tiraParseIntrinsic$ = resVar
          EXIT FUNCTION
        END IF
      END IF
      throwCompilerError "MALFORMED LEN", ASIS, 0

    CASE TOK_MID
      IF startIdx + 5 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          comma1 = findNextTokenAtDepth0(startIdx + 2, endIdx - 1, 256 + ASC(","))
          comma2 = -1
          IF comma1 <> -1 THEN
            comma2 = findNextTokenAtDepth0(comma1 + 1, endIdx - 1, 256 + ASC(","))
          END IF

          IF comma1 <> -1 THEN
            IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
            arg1 = tiraParseExpression$(startIdx + 2, comma1 - 1, allowImplicit)
            IF arg1 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
            IF exprIs.DataType <> TYPE_STRING THEN
              throwCompilerError "MID$ ARG 1 MUST BE STRING", ASIS, 0
              tiraParseIntrinsic$ = "": EXIT FUNCTION
            END IF

            IF comma2 <> -1 THEN
              IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              arg2 = tiraParseExpression$(comma1 + 1, comma2 - 1, allowImplicit)
              IF arg2 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
              arg2 = tiraForceInt$(arg2)

              IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              arg3 = tiraParseExpression$(comma2 + 1, endIdx - 1, allowImplicit)
              IF arg3 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
              arg3 = tiraForceInt$(arg3)
            ELSE
              IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
              arg2 = tiraParseExpression$(comma1 + 1, endIdx - 1, allowImplicit)
              IF arg2 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
              arg2 = tiraForceInt$(arg2)
              arg3 = "&H7FFFFFFF" ' Max integer length to act as missing arg
            END IF

            resVar = tiraDimVar$("T", TYPE_STRING)
            tiraNew TC_INTRINSIC, cTrNum$(TOK_MID) + ", " + resVar + ", " + arg1 + ", " + arg2 + ", " + arg3

            exprIs.DataType = TYPE_STRING
            exprIs.IsTemp = 1
            tiraParseIntrinsic$ = resVar
            EXIT FUNCTION
          END IF
        END IF
      END IF
      throwCompilerError "MALFORMED MID$", ASIS, 0

    CASE TOK_LEFT, TOK_RIGHT
      IF startIdx + 5 <= endIdx THEN
        IF retTokenVal(lineTokens$(startIdx + 1)) = 256 + ASC("(") AND retTokenVal(lineTokens$(endIdx)) = 256 + ASC(")") THEN
          comma1 = findNextTokenAtDepth0(startIdx + 2, endIdx - 1, 256 + ASC(","))

          IF comma1 <> -1 THEN
            IF compileClassicMode = 1 THEN expectedSymType = TYPE_STRING
            arg1 = tiraParseExpression$(startIdx + 2, comma1 - 1, allowImplicit)
            IF arg1 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
            IF exprIs.DataType <> TYPE_STRING THEN
              throwCompilerError "LEFT/RIGHT$ ARG 1 MUST BE STRING", ASIS, 0
              tiraParseIntrinsic$ = "": EXIT FUNCTION
            END IF

            IF compileClassicMode = 1 THEN expectedSymType = TYPE_SINGLE
            arg2 = tiraParseExpression$(comma1 + 1, endIdx - 1, allowImplicit)
            IF arg2 = "" THEN tiraParseIntrinsic$ = "": EXIT FUNCTION
            arg2 = tiraForceInt$(arg2)

            resVar = tiraDimVar$("T", TYPE_STRING)
            tiraNew TC_INTRINSIC, cTrNum$(tVal) + ", " + resVar + ", " + arg1 + ", " + arg2

            exprIs.DataType = TYPE_STRING
            exprIs.IsTemp = 1
            tiraParseIntrinsic$ = resVar
            EXIT FUNCTION
          END IF
        END IF
      END IF
      throwCompilerError "MALFORMED LEFT/RIGHT$", ASIS, 0

    CASE ELSE
      throwCompilerError "UNIMPLEMENTED INTRINSIC OR TOKEN", ASIS, 0
      tiraParseIntrinsic$ = ""

  END SELECT ' tVal

END FUNCTION ' tiraParseIntrinsic$

''''''''''''''''''''''''
SUB tiraOp (opConst AS LONG, destOrIAT$, src1$, src2$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  SELECT CASE opConst

    CASE TC_ADD, TC_SUB, TC_MUL, TC_DIV, TC_IDIV, TC_AND, TC_OR, TC_POW, TC_CONCAT, TC_SHL, TC_SHR, TC_REDRAW, TC_NEG, TC_NOT, TC_CALL
      ' Valid
    CASE ELSE
      throwCompilerError "UNKNOWN OR UNSUPPORTED TIRA CONSTANT IN OP", ASIS, 0
      EXIT SUB

  END SELECT ' opConst

  tiraCmd(t.LineCount) = opConst

  SELECT CASE opConst

    CASE TC_REDRAW
      tiraCode$(t.LineCount) = ""

    CASE TC_NEG, TC_NOT
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
SUB tiraBuildStylePlot (x$, y$)

  DIM lblSkipPlot AS STRING

  lblSkipPlot$ = tiraLabelNew$("SKIP_PLOT")

  tiraOp TC_AND, "!RT_STYLE_BIT", "!RT_STYLE", "32768"
  tiraJmpCond "JE", "!RT_STYLE_BIT", "0", lblSkipPlot$

  tiraCall "RT_PLOT_PIXEL", 3, x$ + ", " + y$ + ", !RT_COLOR"

  tiraLabel lblSkipPlot$

  ' Emulate a 16-bit ROL command purely using TIRA math commands
  tiraOp TC_MUL, "!RT_STYLE_HIGH", "!RT_STYLE", "2"
  tiraOp TC_AND, "!RT_STYLE_HIGH", "!RT_STYLE_HIGH", "65535"
  tiraOp TC_DIV, "!RT_STYLE_LOW", "!RT_STYLE", "32768"
  tiraOp TC_AND, "!RT_STYLE_LOW", "!RT_STYLE_LOW", "1"
  tiraOp TC_OR, "!RT_STYLE", "!RT_STYLE_HIGH", "!RT_STYLE_LOW"

END SUB ' tiraBuildStylePlot

''''''''''''''''''''''''
SUB tiraStart

  IF t.IsActive <> 0 THEN
    throwCompilerError "TIRA QUEUE ALREADY ACTIVE", ASIS, 0
    EXIT SUB
  END IF

  t.IsActive = 1

  ' Initializes the localized 3AC queue for a single BASIC statement
  t.LineCount = 0

  ' Reset the ephemeral TIRA variable counter for this specific statement block
  t.TempCounter = 0

END SUB ' tiraStart

''''''''''''''''''''''''
SUB tiraSwapMem (addr1$, addr2$, sizeMode$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

  tiraCmd(t.LineCount) = TC_SWAP_MEM
  tiraCode$(t.LineCount) = addr1$ + ", " + addr2$ + ", " + sizeMode$
  t.LineCount = t.LineCount + 1

END SUB ' tiraSwapMem

''''''''''''''''''''''''
SUB tiraWriteMem (destAddr$, srcVal$, sizeMode$)

  IF t.LineCount >= MAX_TIRA_LINES THEN
    throwCompilerError "TIRA CODE LIMIT EXCEEDED", ASIS, 0
    EXIT SUB
  END IF

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
        IF LEFT$(remText$, 7) = "$STATIC" THEN defaultArrayDynamic = 0
        IF LEFT$(remText$, 8) = "$DYNAMIC" THEN defaultArrayDynamic = 1
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
              DO WHILE ix <= lineLen
                ch2$ = MID$(wLine$, ix, 1)
                u2$ = UCASE$(ch2$)
                IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") OR ch2$ = "_" THEN
                  numVal$ = numVal$ + ch2$
                  ix = ix + 1
                ELSE
                  EXIT DO
                END IF
              LOOP
              throwCompilerError "invalid token '" + numVal$ + "'", ASIS, 0
              EXIT SUB
            END IF
          END IF
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = numVal$
          lineTokenCount = lineTokenCount + 1
        ELSE
          symVal = 256 + ASC(ch$)
          IF lineTokenCount >= MAX_TOKENS THEN
            throwCompilerError "TOKEN LIMIT", ASIS, 0
            EXIT SUB
          END IF
          lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
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
            lineTokenCount = lineTokenCount + 1
          ELSE
            symVal = 256 + ASC(ch$)
            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
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
                DO WHILE ix <= lineLen
                  ch2$ = MID$(wLine$, ix, 1)
                  u2$ = UCASE$(ch2$)
                  IF (u2$ >= "A" AND u2$ <= "Z") OR (u2$ >= "0" AND u2$ <= "9") OR ch2$ = "_" THEN
                    numVal$ = numVal$ + ch2$
                    ix = ix + 1
                  ELSE
                    EXIT DO
                  END IF
                LOOP
                throwCompilerError "invalid token '" + numVal$ + "'", ASIS, 0
                EXIT SUB
              END IF
            END IF

            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = numVal$
            lineTokenCount = lineTokenCount + 1
          ELSE
            symVal = 256 + ASC(ch$)
            IF lineTokenCount >= MAX_TOKENS THEN
              throwCompilerError "TOKEN LIMIT", ASIS, 0
              EXIT SUB
            END IF
            lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
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
          IF LEFT$(remText$, 7) = "$STATIC" THEN defaultArrayDynamic = 0
          IF LEFT$(remText$, 8) = "$DYNAMIC" THEN defaultArrayDynamic = 1
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
        lineTokenCount = lineTokenCount + 1

      CASE ELSE
        symVal = 256 + ASC(ch$)
        IF lineTokenCount >= MAX_TOKENS THEN
          throwCompilerError "TOKEN LIMIT", ASIS, 0
          EXIT SUB
        END IF
        lineTokens$(lineTokenCount) = CHR$(symVal \ 256) + CHR$(symVal AND 255)
        lineTokenCount = lineTokenCount + 1
        ix = ix + 1

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

  localScrollY = 0

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
    PrintStr closeBtnX + 4, closeBtnY + 3, "X", 15, -1

    IF mouse.Released1 THEN
      IF mouseWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) AND mouseDownWithinBoxBounds(closeBtnX, closeBtnY, closeBtnW, closeBtnH) THEN
        EXIT DO
      END IF
    END IF

    PrintStr boxX + (boxW \ 2) - (15 * 4), boxY + 3, "SUBS / FUNCTIONS", 14, -1
    LINE (boxX, boxY + 13)-(boxX + boxW - 1, boxY + 13), 15

    itemH = 10
    maxLines = (boxH - 15) \ itemH

    ' Scrollbar
    scrollBarX = boxX + boxW - 12
    scrollBarY = boxY + 14
    scrollBarW = 12
    scrollBarH = boxH - 15

    drawBorderBox scrollBarX, scrollBarY, scrollBarW, scrollBarH, 15, 0
    PrintChr scrollBarX + 2, scrollBarY + 1, CHR$(24), 15, -1
    PrintChr scrollBarX + 2, scrollBarY + scrollBarH - 9, CHR$(25), 15, -1

    IF uiSubCount > maxLines THEN
      scrollRange = uiSubCount - maxLines
      thumbH = scrollBarH - 20
      thumbMaxH = thumbH
      thumbSize = (maxLines * thumbMaxH) \ uiSubCount
      IF thumbSize < 8 THEN thumbSize = 8
      thumbY = scrollBarY + 10 + ((localScrollY * (thumbMaxH - thumbSize)) \ scrollRange)
      LINE (scrollBarX + 1, thumbY)-(scrollBarX + scrollBarW - 2, thumbY + thumbSize - 1), 15, BF
    ELSE
      LINE (scrollBarX + 1, scrollBarY + 10)-(scrollBarX + scrollBarW - 2, scrollBarY + scrollBarH - 11), 15, BF
    END IF

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

          IF mouse.Released1 AND mouseDownWithinBoxBounds(boxX + 2, itemY, boxW - 16, itemH) THEN
            ' Update main UI funcScrollY to ensure right-hand list brings the sub into view
            IF subIdx < funcScrollY OR subIdx >= funcScrollY + 12 THEN
              funcScrollY = subIdx - 5
              IF funcScrollY < 0 THEN funcScrollY = 0
              maxFuncScroll = uiSubCount - 12
              IF maxFuncScroll < 0 THEN maxFuncScroll = 0
              IF funcScrollY > maxFuncScroll THEN funcScrollY = maxFuncScroll
              ' Redraw the right list now so it reflects the new scroll position
              drawFuncListPMI
            END IF

            ' Flash the right-hand box list simultaneously
            funcListBoxX = RIGHT_BOX_X
            funcListBoxY = editor.StartY
            funcListBoxW = 122
            rowY = funcListBoxY + 3 + ((subIdx - funcScrollY + 1) * 10)
            LINE (funcListBoxX + 1, rowY)-(funcListBoxX + funcListBoxW - 11, rowY + 9), 1, BF
            PrintStr funcListBoxX + RIGHT_BOX_SPACING, rowY + 1, LEFT$(uiSubName$(subIdx), 13), 15, -1

            ' Flash the modal list
            LINE (boxX + 2, itemY)-(boxX + boxW - 15, itemY + itemH - 1), 1, BF
            PrintStr boxX + 8, itemY + 1, sOutName$, 15, -1

            _DISPLAY
            tGoal = TIMER + UI_FLASH_TIME: DO WHILE TIMER < tGoal: LOOP

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

        PrintStr boxX + 8, itemY + 1, sOutName$, 11, -1
      END IF
    NEXT

    _DISPLAY

    kVal = keyCheck("ESC")
    IF kVal = 27 THEN
      waitKeyRelease "ESC"
      EXIT DO
    END IF

    ' Handle scrollbar clicks
    IF mouse.Released1 THEN
      IF mouseWithinBoxBounds(scrollBarX, scrollBarY, scrollBarW, 10) THEN
        localScrollY = localScrollY - 1
        IF localScrollY < 0 THEN localScrollY = 0
      END IF
      IF mouseWithinBoxBounds(scrollBarX, scrollBarY + scrollBarH - 10, scrollBarW, 10) THEN
        localScrollY = localScrollY + 1
        maxScroll = uiSubCount - maxLines
        IF maxScroll < 0 THEN maxScroll = 0
        IF localScrollY > maxScroll THEN localScrollY = maxScroll
      END IF
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
  arraypadUpTo PE_FILE_HEADER_OFFSET + wTextRawSize + impTbl.idataRawSize, 0

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
  arraypadUpTo PE_FILE_HEADER_OFFSET, 0

END SUB ' writePEHeader

''''''''''''''''''''''''
SUB return2 (wVal)

  ' Return the global secondary return variable

  returnF2data = wVal

END SUB ' return2

''''''''''''''''''''''''
FUNCTION return3

  ' Return the global tertiary return value
  return3 = returnF3data

END FUNCTION ' return3


''''''''''''''''''''''''
FUNCTION returnedData2

  returnedData2 = returnF2data

END FUNCTION ' returnedData2

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

  PrintStr boxX + 8, boxY + 8, wStr1$, 15, 0
  IF wStr2$ <> "" THEN PrintStr boxX + 8, boxY + 18, wStr2$, 15, 0

  END

END SUB ' ESCAPETEXT2

