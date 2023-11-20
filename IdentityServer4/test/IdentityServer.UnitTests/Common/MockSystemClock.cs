using System;

namespace IdentityServer.UnitTests.Common
{
    class MockSystemClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; }

        public DateTimeOffset UtcNow => Now;

        #region Overrides of TimeProvider

        public override DateTimeOffset GetUtcNow() => Now;

        #endregion
    }
}
