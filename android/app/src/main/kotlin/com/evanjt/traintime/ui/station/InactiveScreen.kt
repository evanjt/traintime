package com.evanjt.traintime.ui.station

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Tram
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.padding

@Composable
fun InactiveScreen(onResume: () -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
    ) {
        Icon(
            Icons.Filled.Tram,
            contentDescription = null,
            tint = secondary,
            modifier = Modifier.size(56.dp),
        )
        Text(
            "Inactive",
            color = secondary,
            fontSize = 22.sp,
            modifier = Modifier.padding(top = 16.dp),
        )
        OutlinedButton(
            onClick = onResume,
            modifier = Modifier.padding(top = 16.dp),
        ) {
            Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
            Text("Resume", modifier = Modifier.padding(start = 6.dp))
        }
    }
}
