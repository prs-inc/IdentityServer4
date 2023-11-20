// Copyright (c) Brock Allen & Dominick Baier. All rights reserved.
// Licensed under the Apache License, Version 2.0. See LICENSE in the project root for license information.


using System;

namespace IdentityServer.UnitTests.Common
{
    internal class StubClock : TimeProvider
    {
        public Func<DateTime> UtcNowFunc = () => DateTime.UtcNow;
        public DateTimeOffset UtcNow => new DateTimeOffset(UtcNowFunc());

        #region Overrides of TimeProvider

        public override DateTimeOffset GetUtcNow() => UtcNow;

        #endregion
    }
}
