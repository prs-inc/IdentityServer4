namespace System.Net.Http;

#pragma warning disable 1591

public static class HttpRequestOptionsExtensions
{
    public static void Set<T>(this HttpRequestOptions options, string key, T value)
    {
        options.Set(new HttpRequestOptionsKey<T>(key), value);
    }
}