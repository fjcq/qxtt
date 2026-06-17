// 测试 Uint8List backing buffer 对齐行为
import 'dart:typed_data';

void main()
{
    print('Test Uint8List backing buffer alignment:');
    for (var n in [100, 1000, 10000, 55148, 100000, 160024, 99999])
    {
        final u = Uint8List(n);
        final diff = u.buffer.lengthInBytes - n;
        print('  n=$n: length=${u.length}, lengthInBytes=${u.lengthInBytes}, '
            'buffer.lengthInBytes=${u.buffer.lengthInBytes}, diff=$diff');
    }

    print('');
    print('Test Uint32List backing buffer alignment:');
    for (var n in [100, 1000, 10000, 13787, 50000])
    {
        final u = Uint32List(n);
        final diff = u.buffer.lengthInBytes - n * 4;
        print('  n=$n (bytes=${n*4}): length=${u.length}, lengthInBytes=${u.lengthInBytes}, '
            'buffer.lengthInBytes=${u.buffer.lengthInBytes}, diff=$diff');
    }
}
