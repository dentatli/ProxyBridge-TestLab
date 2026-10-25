namespace ProxyBridge.TestLab.TrafficEngine;

// Unlike BufferedStream, the reader buffer is never shared with the concurrent writer.
internal sealed class ReadBufferedDuplexStream(Stream inner) : Stream
{
    private readonly byte[] buffer = new byte[8192];
    private int position, length;
    public override bool CanRead => inner.CanRead;
    public override bool CanWrite => inner.CanWrite;
    public override bool CanSeek => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    public override async ValueTask<int> ReadAsync(Memory<byte> destination, CancellationToken token = default)
    {
        if (destination.Length == 0) return 0;
        if (position == length)
        {
            position = length = 0;
            if (destination.Length >= buffer.Length) return await inner.ReadAsync(destination, token);
            length = await inner.ReadAsync(buffer, token); if (length == 0) return 0;
        }
        var count = Math.Min(destination.Length, length - position); buffer.AsMemory(position, count).CopyTo(destination); position += count; return count;
    }
    public override Task<int> ReadAsync(byte[] destination, int offset, int count, CancellationToken token) => ReadAsync(destination.AsMemory(offset, count), token).AsTask();
    public override int Read(byte[] destination, int offset, int count) => ReadAsync(destination.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
    public override ValueTask WriteAsync(ReadOnlyMemory<byte> source, CancellationToken token = default) => inner.WriteAsync(source, token);
    public override Task WriteAsync(byte[] source, int offset, int count, CancellationToken token) => inner.WriteAsync(source, offset, count, token);
    public override void Write(byte[] source, int offset, int count) => inner.Write(source, offset, count);
    public override void Flush() => inner.Flush();
    public override Task FlushAsync(CancellationToken token) => inner.FlushAsync(token);
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
    public override ValueTask DisposeAsync() => inner.DisposeAsync();
}
