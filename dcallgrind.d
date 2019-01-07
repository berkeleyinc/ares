import std.array;
import std.stdio;
import std.demangle;
import std.regex;
import std.conv;

auto re = ctRegex!(`(_D\d[\w_]+)`);

void main(string[] args)
{
    auto isStdin = args.length == 1;
    auto inFile = isStdin ? stdin : File(args[1]);
    auto outFile = isStdin ? stdout : File(args[1] ~ ".demangled", "w");
    foreach (l; inFile.byLine(KeepTerminator.yes))
        outFile.write(replace!(a => demangle(to!string(a.hit)).replace("\"", "''"))(l, re));
}
