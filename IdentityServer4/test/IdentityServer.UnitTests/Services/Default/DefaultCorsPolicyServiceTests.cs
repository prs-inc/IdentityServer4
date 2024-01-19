// Copyright (c) Brock Allen & Dominick Baier. All rights reserved.
// Licensed under the Apache License, Version 2.0. See LICENSE in the project root for license information.


using System.Threading.Tasks;
using FluentAssertions;
using IdentityServer.UnitTests.Common;
using IdentityServer4.Services;
using Xunit;

namespace IdentityServer.UnitTests.Services.Default
{
    public class DefaultCorsPolicyServiceTests
    {
        private const string Category = "DefaultCorsPolicyService";

        private DefaultCorsPolicyService subject;

        public DefaultCorsPolicyServiceTests()
        {
            subject = new DefaultCorsPolicyService(TestLogger.Create<DefaultCorsPolicyService>());
        }

        [Fact]
        [Trait("Category", Category)]
        public async Task IsOriginAllowed_null_param_ReturnsFalse()
        {
            var result = await subject.IsOriginAllowedAsync(null);
            result.Should().Be(false);
            
            result = await subject.IsOriginAllowedAsync(string.Empty);
            result.Should().Be(false);
            
            result = await subject.IsOriginAllowedAsync("    ");
            result.Should().Be(false);
        }

        [Fact]
        [Trait("Category", Category)]
        public async Task IsOriginAllowed_OriginIsAllowed_ReturnsTrue()
        {
            subject.AllowedOrigins.Add("http://foo");
            var result = await subject.IsOriginAllowedAsync("http://foo");
            result.Should().Be(true);
        }

        [Fact]
        [Trait("Category", Category)]
        public async Task IsOriginAllowed_OriginIsNotAllowed_ReturnsFalse()
        {
            subject.AllowedOrigins.Add("http://foo");
            var result = await subject.IsOriginAllowedAsync("http://bar");
            result.Should().Be(false);
        }

        [Fact]
        [Trait("Category", Category)]
        public async Task IsOriginAllowed_OriginIsInAllowedList_ReturnsTrue()
        {
            subject.AllowedOrigins.Add("http://foo");
            subject.AllowedOrigins.Add("http://bar");
            subject.AllowedOrigins.Add("http://baz");
            var result = await subject.IsOriginAllowedAsync("http://bar"); 
            result.Should().Be(true);
        }

        [Fact]
        [Trait("Category", Category)]
        public async Task IsOriginAllowed_OriginIsNotInAllowedList_ReturnsFalse()
        {
            subject.AllowedOrigins.Add("http://foo");
            subject.AllowedOrigins.Add("http://bar");
            subject.AllowedOrigins.Add("http://baz");
            var result = await subject.IsOriginAllowedAsync("http://quux");
            result.Should().Be(false);
        }

        [Fact]
        [Trait("Category", Category)]
        public async Task IsOriginAllowed_AllowAllTrue_ReturnsTrue()
        {
            subject.AllowAll = true;
            var result = await subject.IsOriginAllowedAsync("http://foo");
            result.Should().Be(true);
        }
    }
}
