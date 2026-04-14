class TKLMutatorv2TcpLinkClient extends BufferedTcpLink
    config(Mutator_TKLMutatorv2_Server);

// See: https://github.com/tuokri/tklserver
var config string TKLServerHost;
var config int TKLServerPort;
var config int MaxRetries;
var config string UniqueRS2ServerId;

var int Retries;
var bool bRetryOnClosed;
var bool bShuttingDown;

// Must store reference to parent in order to start
// Open() cancellation timer in case the Open() call fails.
// When Open() call fails, it will block and spam log
// with errors. Timers in this class will also not work
// while the call to Open() is blocking.
var TKLMutatorv2 Parent;

static final function StaticFirstTimeConfig()
{
    if ((Len(default.TKLServerHost) == 0)
        && (default.TKLServerPort == 0)
        && (default.MaxRetries == 0)
        && (Len(default.UniqueRS2ServerId) == 0))
    {
        `log("[TKLMutatorv2TcpLinkClient]: setting config values to first time defaults");
        default.TKLServerHost = "localhost";
        default.TKLServerPort = 8586;
        default.MaxRetries = 5;
        default.UniqueRS2ServerId = "0000";
        StaticSaveConfig();
    }
}

final function FirstTimeConfig()
{
    if ((Len(TKLServerHost) == 0)
        && (TKLServerPort == 0)
        && (MaxRetries == 0)
        && (Len(UniqueRS2ServerId) == 0))
    {
        `log("[TKLMutatorv2TcpLinkClient]: setting config values to first time defaults");
        TKLServerHost = "localhost";
        TKLServerPort = 8586;
        MaxRetries = 5;
        UniqueRS2ServerId = "0000";
    }
}

event PreBeginPlay()
{
    FirstTimeConfig();
    SaveConfig();
    super.PreBeginPlay();
}

final function ResolveServer()
{
    `log("[TKLMutatorv2TcpLinkClient]: resolving: " $ TKLServerHost);
    Resolve(TKLServerHost);
}

event PostBeginPlay()
{
    super.PostBeginPlay();

    bRetryOnClosed = True;

    if (MaxRetries < 0)
    {
        MaxRetries = `MAX_RESOLVE_RETRIES;
        `log("[TKLMutatorv2TcpLinkClient]: invalid MaxRetries, defaulting to: " $ `MAX_RESOLVE_RETRIES);
    }

    if (Len(UniqueRS2ServerId) != 4)
    {
        `log("[TKLMutatorv2TcpLinkClient]: invalid UniqueRS2ServerId, must be exactly 4 characters long");
        return;
    }

    ResolveServer();

    super.PostBeginPlay();
}

event Resolved(IpAddr Addr)
{
    local int BoundPort;

    if (bShuttingDown)
        return;

    `log("[TKLMutatorv2TcpLinkClient]: " $ TKLServerHost $ " resolved to " $ IpAddrToString(Addr));
    Addr.Port = TKLServerPort;

    BoundPort = BindPort();
    if (BoundPort == 0)
    {
        `log("[TKLMutatorv2TcpLinkClient]: failed to bind port");
        Retry();
        return;
    }

    `log("[TKLMutatorv2TcpLinkClient]: bound to port: " $ BoundPort);

    if (!Open(Addr))
    {
        `log("[TKLMutatorv2TcpLinkClient]: failed to open connection, retrying in 5 seconds");
        Retry();
    }
}

event ResolveFailed()
{
    if (bShuttingDown)
        return;

    `log("[TKLMutatorv2TcpLinkClient]: unable to resolve, retrying in 5 seconds " $ TKLServerHost);
    Retry();
}

event Opened()
{
    `log("[TKLMutatorv2TcpLinkClient]: connection opened");
    bAcceptNewData = True;
}

event Closed()
{
    if (bShuttingDown)
        return;

    if (bRetryOnClosed)
    {
        `log("[TKLMutatorv2TcpLinkClient]: connection closed unexpectedly, retrying in 5 seconds");
        Retry();
    }
    else
    {
        `log("[TKLMutatorv2TcpLinkClient]: connection closed");
        bAcceptNewData = False;
    }
}

final function BeginShutdown()
{
    bShuttingDown  = True;
    bRetryOnClosed = False;
    ClearTimer('ResolveServer');
    Close();
}

function bool Close()
{
    bRetryOnClosed = False;
    return super.Close();
}

function bool SendBufferedData(string Text)
{
    // if (!IsConnected())
    // {
    //     `log("[TKLMutatorv2TcpLinkClient]: attempting to queue data but connection is not open");
    // }
    Text = UniqueRS2ServerId $ Text $ LF;
    return super.SendBufferedData(Text);
}

function Tick(float DeltaTime)
{
    DoBufferQueueIO();
    super.Tick(DeltaTime);
}

final function Retry()
{
    if (Retries > MaxRetries)
    {
        `log("[TKLMutatorv2TcpLinkClient]: max retries exceeded (" $ MaxRetries $ ")");
        Close();
        return;
    }
    Retries++;
    SetTimer(5.0, False, 'ResolveServer');
    Parent.SetCancelOpenLinkTimer(7.0);
}

defaultproperties
{
    TickGroup=TG_DuringAsyncWork
}
