package ch.traintime.phone.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ch.traintime.shared.models.TransportMode
import ch.traintime.phone.viewmodels.PhoneViewModel

@Composable
fun SettingsDialog(viewModel: PhoneViewModel, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color(0xFF1A1A1A),
        title = { Text("Settings", color = Color.White) },
        text = {
            Column {
                Text("Default Mode", fontSize = 14.sp, color = Color.Gray)
                Spacer(modifier = Modifier.height(8.dp))
                TransportMode.entries.forEach { mode ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                viewModel.updateDefaultMode(mode)
                            }
                            .padding(vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = mode.label, fontSize = 16.sp, color = Color.White)
                        Spacer(modifier = Modifier.weight(1f))
                        if (viewModel.defaultMode == mode) {
                            Icon(
                                Icons.Default.Check,
                                contentDescription = null,
                                tint = Color(0xFF55AAFF)
                            )
                        }
                    }
                }
                Spacer(modifier = Modifier.height(16.dp))
                HorizontalDivider(color = Color(0xFF444444))
                Spacer(modifier = Modifier.height(12.dp))
                Row {
                    Text("Version", fontSize = 14.sp, color = Color.Gray)
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = viewModel.getApplication<android.app.Application>().packageManager
                            .getPackageInfo(viewModel.getApplication<android.app.Application>().packageName, 0).versionName ?: "?",
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Done")
            }
        }
    )
}
