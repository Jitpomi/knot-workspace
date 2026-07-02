package com.example.amos

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.amos_core.AmosDirectorListener
import uniffi.amos_core.AmosEventListener
import uniffi.amos_core.Core
import uniffi.amos_core.StreamConfig
import java.io.File
import java.util.UUID

data class ParticipantInfo(
    val id: String,
    val name: String,
    val device: String
)

data class AppUiState(
    val isDirector: Boolean = false,
    val isRunning: Boolean = false,
    val isConnected: Boolean = false,
    val isRecording: Boolean = false,
    val ticketText: String = "",
    val displayName: String = android.os.Build.MODEL,
    val deviceType: String = "Android Device",
    val statusMessage: String = "Ready",
    val localStreamId: String? = null,
    val connectedClients: List<String> = emptyList(),
    val clientsMap: Map<String, ParticipantInfo> = emptyMap()
)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    
    private val dataDir = File(application.filesDir, "AmosRecordings").apply { mkdirs() }.absolutePath
    private val core: Core = Core(dataDir)
    
    private val _uiState = MutableStateFlow(AppUiState())
    val uiState: StateFlow<AppUiState> = _uiState.asStateFlow()



    init {
        _uiState.update { it.copy(statusMessage = "Ready. Node ID: ${core.nodeId()}") }
    }

    fun setMode(isDirector: Boolean) {
        _uiState.update { it.copy(isDirector = isDirector) }
    }

    fun updateDisplayName(name: String) {
        _uiState.update { it.copy(displayName = name) }
    }

    fun updateDeviceType(device: String) {
        _uiState.update { it.copy(deviceType = device) }
    }

    // Director controls
    fun startDirector() {
        try {
            val directorListener = object : AmosDirectorListener {
                override fun onClientConnected(clientId: String, participantId: String, displayName: String, deviceType: String) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update { state ->
                            val updatedClients = if (state.connectedClients.contains(clientId)) state.connectedClients else state.connectedClients + clientId
                            val updatedMap = state.clientsMap + (clientId to ParticipantInfo(clientId, displayName, deviceType))
                            state.copy(
                                connectedClients = updatedClients,
                                clientsMap = updatedMap,
                                statusMessage = "Participant joined: $displayName"
                            )
                        }
                    }
                }

                override fun onClientDisconnected(clientId: String) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update { state ->
                            state.copy(
                                connectedClients = state.connectedClients - clientId,
                                clientsMap = state.clientsMap - clientId,
                                statusMessage = "Participant disconnected"
                            )
                        }
                    }
                }

                override fun onClientStreamConfigured(clientId: String, streamId: String, config: StreamConfig) {
                    // No-op
                }

                override fun onFrameReceived(clientId: String, streamId: String, frameType: Byte, timestampMs: Long, payload: ByteArray) {
                    // No-op
                }

                override fun onClientVideoStateChanged(clientId: String, isVideoOn: Boolean, isScreenSharing: Boolean) {
                    // No-op
                }

                override fun onForceKeyframe(streamId: String) {
                    // No-op
                }

                override fun onCustomMessage(clientId: String, variant: String, data: String) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update { it.copy(statusMessage = "Custom msg from $clientId: [$variant] $data") }
                    }
                }
            }

            val ticket = core.startDirector(directorListener)
            _uiState.update {
                it.copy(
                    isRunning = true,
                    ticketText = ticket,
                    statusMessage = "Director running. Share ticket to connect!"
                )
            }
        } catch (e: Exception) {
            _uiState.update { it.copy(statusMessage = "Failed to start director: ${e.message}") }
        }
    }

    fun stopDirector() {
        try {
            core.stopDirector()
            _uiState.update {
                it.copy(
                    isRunning = false,
                    ticketText = "",
                    connectedClients = emptyList(),
                    clientsMap = emptyMap(),
                    statusMessage = "Director stopped."
                )
            }
        } catch (e: Exception) {
            _uiState.update { it.copy(statusMessage = "Failed to stop director: ${e.message}") }
        }
    }

    fun toggleRecording() {
        val newState = !_uiState.value.isRecording
        try {
            core.setRecordingState(newState)
            _uiState.update {
                it.copy(
                    isRecording = newState,
                    statusMessage = if (newState) "Recording started globally" else "Recording stopped."
                )
            }
        } catch (e: Exception) {
            _uiState.update { it.copy(statusMessage = "Recording toggle failed: ${e.message}") }
        }
    }

    fun requestKeyframe(clientId: String) {
        try {
            core.requestKeyframe(clientId, "1")
            _uiState.update { it.copy(statusMessage = "Requested keyframe from $clientId") }
        } catch (e: Exception) {
            _uiState.update { it.copy(statusMessage = "Keyframe request failed: ${e.message}") }
        }
    }

    // Participant controls
    fun connectToDirector(ticket: String) {
        _uiState.update { it.copy(statusMessage = "Connecting...") }
        try {
            val eventListener = object : AmosEventListener {
                override fun onForceKeyframe(streamId: String) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update { it.copy(statusMessage = "Host requested keyframe!") }
                    }
                }

                override fun onRecordingStateChanged(isRecording: Boolean) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update {
                            it.copy(
                                isRecording = isRecording,
                                statusMessage = if (isRecording) "Recording started by Host!" else "Recording stopped by Host."
                            )
                        }
                    }
                }

                override fun onConnectionStatusChanged(connected: Boolean) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update {
                            it.copy(
                                isConnected = connected,
                                statusMessage = if (connected) "Connected to session." else "Disconnected from session."
                            )
                        }
                        if (!connected) {
                            stopStreaming()
                        }
                    }
                }

                override fun onFrameReceived(clientId: String, streamId: String, frameType: UByte, timestampMs: ULong, payload: ByteArray) {
                    // No-op
                }

                override fun onHostInfoChanged(producerName: String, isVideoOn: Boolean, isScreenSharing: Boolean) {
                    // No-op
                }

                override fun onHostVideoStateChanged(isVideoOn: Boolean, isScreenSharing: Boolean) {
                    // No-op
                }

                override fun onClientConnected(clientId: String, participantId: String, displayName: String, deviceType: String) {
                    // No-op
                }

                override fun onClientDisconnected(clientId: String) {
                    // No-op
                }

                override fun onClientVideoStateChanged(clientId: String, isVideoOn: Boolean, isScreenSharing: Boolean) {
                    // No-op
                }

                override fun onTalkbackChanged(enabled: Boolean) {
                    // No-op
                }

                override fun onPrompterChanged(text: String) {
                    // No-op
                }

                override fun onTallyChanged(streamId: String, isLive: Boolean, isPreview: Boolean) {
                    // No-op
                }

                override fun onHostStreamConfigured(streamId: String, config: StreamConfig) {
                    // No-op
                }

                override fun onClientStreamConfigured(clientId: String, streamId: String, config: StreamConfig) {
                    // No-op
                }

                override fun onSoundTriggered(soundName: String, targetOutput: String) {
                    // No-op
                }

                override fun onCustomMessage(clientId: String, variant: String, data: String) {
                    viewModelScope.launch(Dispatchers.Main) {
                        _uiState.update { it.copy(statusMessage = "Custom msg from $clientId: [$variant] $data") }
                    }
                }
            }

            core.connectToDirector(
                ticket = ticket,
                participantId = UUID.randomUUID().toString(),
                displayName = _uiState.value.displayName,
                deviceType = _uiState.value.deviceType,
                sessionId = "session_default",
                listener = eventListener
            )
        } catch (e: Exception) {
            _uiState.update { it.copy(statusMessage = "Connection failed: ${e.message}") }
        }
    }

    fun startStreaming() {
        val config = StreamConfig(
            streamId = null,
            sourceType = "camera",
            name = "Android Camera",
            codec = "h264",
            width = 1920,
            height = 1080,
            audioProfile = null,
            sampleRate = null,
            channels = null,
            echoCancellation = null,
            noiseSuppression = null
        )
        try {
            val streamId = core.publishStream(config)
            _uiState.update {
                it.copy(
                    localStreamId = streamId,
                    statusMessage = "Streaming active. ID: $streamId"
                )
            }
        } catch (e: Exception) {
            _uiState.update { it.copy(statusMessage = "Streaming failed: ${e.message}") }
        }
    }

    private fun stopStreaming() {
        val streamId = _uiState.value.localStreamId ?: return
        try {
            core.closeStream(streamId)
        } catch (e: Exception) {
            // Ignored
        }
        _uiState.update { it.copy(localStreamId = null) }
    }


}
