package com.evanjt.traintime.data.api

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class FormationDtoTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun numbers(body: String) =
        json.decodeFromString<FormationResponseDto>(body).toFormation()!!.wagons.map { it.number }

    @Test
    fun `a car the feed does not number has no number`() {
        val body = """
            {"track": "2", "sectors": ["A"], "wagons": [
              {"position": 1, "number": 1, "class": 2, "sector": "A", "numberUnknown": true},
              {"position": 2, "number": 12, "class": 2, "sector": "A"}
            ]}
        """.trimIndent()
        assertEquals(listOf(null, 12), numbers(body))
    }

    @Test
    fun `a payload without the flag keeps every number`() {
        val body = """
            {"track": "2", "sectors": ["A"], "wagons": [
              {"position": 1, "number": 5, "class": 2, "sector": "A"},
              {"position": 2, "number": 4, "class": 1, "sector": "A"}
            ]}
        """.trimIndent()
        assertEquals(listOf(5, 4), numbers(body))
    }
}
