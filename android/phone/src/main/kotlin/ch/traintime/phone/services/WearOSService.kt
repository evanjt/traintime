package ch.traintime.phone.services

import android.content.Context
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

class WearOSService(private val context: Context) {

    companion object {
        private const val TRACK_PATH = "/traintime/track"
    }

    suspend fun getConnectedNodes(): List<Node> {
        return try {
            Wearable.getNodeClient(context).connectedNodes.await()
        } catch (_: Exception) {
            emptyList()
        }
    }

    suspend fun sendMessage(nodeId: String, data: ByteArray): Boolean {
        return try {
            Wearable.getMessageClient(context)
                .sendMessage(nodeId, TRACK_PATH, data)
                .await()
            true
        } catch (_: Exception) {
            false
        }
    }
}
