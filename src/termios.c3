module misc::termios;

const int TCSANOW     =  0;
const int TCSADRAIN   =  1;
const int TCSAFLUSH   =  2;

const int NCCS        =  20;

struct Termios @cname("termios"){
	ulong        c_iflag;        /* input flags */
	ulong        c_oflag;        /* output flags */
	ulong        c_cflag;        /* control flags */
	ulong        c_lflag;        /* local flags */
	char[NCCS]   c_cc;           /* control chars */
	ulong        c_ispeed;       /* input speed */
	ulong        c_ospeed;       /* output speed */
}

const int ECHOKE    = 0x00000001;
const int ECHOE     = 0x00000002;
const int ECHOK     = 0x00000004;
const int ECHO      = 0x00000008;
const int ECHONL    = 0x00000010;
const int ECHOPRT   = 0x00000020;
const int ECHOCTL   = 0x00000040;
const int ISIG      = 0x00000080;
const int ICANON    = 0x00000100;
const int ALTWERASE = 0x00000200;
const int IEXTEN    = 0x00000400;
const int EXTPROC   = 0x00000800;
const int TOSTOP    = 0x00400000;
const int FLUSHO    = 0x00800000;
const int NOKERNINFO= 0x02000000;
const int PENDIN    = 0x20000000;
const long NOFLSH    = 0x80000000;

extern fn ulong cfgetispeed(Termios* t)                    @cname("cfgetispeed");
extern fn ulong cfgetospeed(Termios* t)                    @cname("cfgetospeed");
extern fn int   cfsetispeed(Termios* t, ulong speed)       @cname("cfsetispeed");
extern fn int   cfsetospeed(Termios* t, ulong speed)       @cname("cfsetospeed");

extern fn int   tcgetattr(int fd, Termios* t)              @cname("tcgetattr");
extern fn int   tcsetattr(int fd, int action, Termios* t)  @cname("tcsetattr");
extern fn int   tcdrain(int fd)                            @cname("tcdrain");
extern fn int   tcflow(int fd, int action)                 @cname("tcflow");
extern fn int   tcflush(int fd, int queue_selector)        @cname("tcflush");
extern fn int   tcsendbreak(int fd, int duration)          @cname("tcsendbreak");
