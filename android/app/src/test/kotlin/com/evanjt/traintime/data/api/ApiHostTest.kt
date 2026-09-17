package com.evanjt.traintime.data.api

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ApiHostTest {
    @Test
    fun `blank means the default`() {
        assertEquals("", ApiHost.normalise(""))
        assertEquals("", ApiHost.normalise("   "))
        assertEquals(ApiHost.DEFAULT, ApiHost.effective(""))
    }

    @Test
    fun `https origin is kept`() {
        assertEquals("https://api.example.ch", ApiHost.normalise("https://api.example.ch"))
        assertEquals("https://api.example.ch:8443", ApiHost.normalise("https://api.example.ch:8443"))
    }

    @Test
    fun `whitespace and trailing slash are stripped`() {
        assertEquals("https://api.example.ch", ApiHost.normalise("  https://api.example.ch/  "))
    }

    @Test
    fun `http is rejected`() {
        assertNull(ApiHost.normalise("http://api.example.ch"))
    }

    @Test
    fun `path query and fragment are rejected`() {
        assertNull(ApiHost.normalise("https://api.example.ch/v1"))
        assertNull(ApiHost.normalise("https://api.example.ch?x=1"))
        assertNull(ApiHost.normalise("https://api.example.ch#top"))
    }

    @Test
    fun `plain words are rejected`() {
        assertNull(ApiHost.normalise("api.example.ch"))
        assertNull(ApiHost.normalise("not a url"))
    }
}
