package com.example.amos

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.amos.ui.theme.AmosTheme
import kotlin.random.Random

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        enableEdgeToEdge()
        setContent {
            AmosTheme(darkTheme = true) {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    val viewModel: AppViewModel = viewModel()
                    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

                    GoogleMeetScreen(
                        uiState = uiState,
                        viewModel = viewModel,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoogleMeetScreen(
    uiState: AppUiState,
    viewModel: AppViewModel,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    var showSettingsSheet by remember { mutableStateOf(false) }
    var isMuted by remember { mutableStateOf(false) }
    var isCameraOff by remember { mutableStateOf(false) }

    // Google Meet Palette
    val meetBackground = Color(0xFF202124)
    val meetControlBackground = Color(0xFF3C4043)
    val meetControlRed = Color(0xFFEA4335)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(meetBackground)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.2f))
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(if (uiState.isConnected || uiState.isRunning) Color.Green else Color.Gray)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = if (uiState.isDirector) "Host Studio" else "Guest Node",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 14.sp
                    )
                }

                if (uiState.isRecording) {
                    Row(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color.Red.copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(Color.Red)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "REC",
                            color = Color.Red,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }

            // Main Video Stage
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(16.dp),
                contentAlignment = Alignment.Center
            ) {
                if (uiState.isDirector) {
                    if (!uiState.isRunning) {
                        GreenRoomPlaceholder("Host Off-Air", "Open settings below to boot your host recording deck.")
                    } else if (uiState.connectedClients.isEmpty()) {
                        GreenRoomPlaceholder("Waiting for Guest...", "Copy your joining code and send it to your participant.")
                    } else {
                        DirectorClientsGrid(uiState, viewModel)
                    }
                } else {
                    if (!uiState.isConnected) {
                        GreenRoomPlaceholder("Green Room", "Open settings to enter name and connect with ticket JSON.")
                    } else {
                        ParticipantVideoStage(uiState, isCameraOff, isMuted)
                    }
                }
            }

            // Floating Controls Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 24.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(28.dp))
                        .background(Color.Black.copy(alpha = 0.3f))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(28.dp))
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // Mute Button
                    CircularControlButton(
                        icon = if (isMuted) Icons.Default.MicOff else Icons.Default.Mic,
                        isActive = !isMuted,
                        activeColor = meetControlBackground,
                        inactiveColor = meetControlRed,
                        onClick = { isMuted = !isMuted }
                    )

                    // Video Button
                    CircularControlButton(
                        icon = if (uiState.localStreamId == null || isCameraOff) Icons.Default.VideoCall else Icons.Default.Videocam,
                        isActive = (uiState.localStreamId != null && !isCameraOff),
                        activeColor = meetControlBackground,
                        inactiveColor = meetControlRed,
                        onClick = {
                            if (uiState.isConnected) {
                                if (uiState.localStreamId == null) {
                                    viewModel.startStreaming()
                                    isCameraOff = false
                                } else {
                                    isCameraOff = !isCameraOff
                                }
                            } else {
                                isCameraOff = !isCameraOff
                            }
                        }
                    )

                    // Record Toggle (Director only)
                    if (uiState.isDirector && uiState.isRunning) {
                        CircularControlButton(
                            icon = Icons.Default.RadioButtonChecked,
                            isActive = !uiState.isRecording,
                            activeColor = meetControlBackground,
                            inactiveColor = meetControlRed,
                            onClick = { viewModel.toggleRecording() }
                        )
                    }

                    // Settings Gear Button
                    CircularControlButton(
                        icon = Icons.Default.Settings,
                        isActive = showSettingsSheet,
                        activeColor = Color(0xFF1A73E8),
                        inactiveColor = meetControlBackground,
                        onClick = { showSettingsSheet = true }
                    )

                    // End Session Button
                    CircularControlButton(
                        icon = Icons.Default.CallEnd,
                        isActive = false,
                        activeColor = meetControlRed,
                        inactiveColor = meetControlRed,
                        onClick = {
                            if (uiState.isDirector) {
                                viewModel.stopDirector()
                            } else {
                                viewModel.connectToDirector("") // Triggers disconnect
                            }
                        }
                    )
                }
            }
        }

        // Settings Sheet Modal
        if (showSettingsSheet) {
            ModalBottomSheet(
                onDismissRequest = { showSettingsSheet = false },
                containerColor = Color(0xFF292A2D)
            ) {
                SettingsSheetContent(
                    uiState = uiState,
                    viewModel = viewModel,
                    onDismiss = { showSettingsSheet = false },
                    onCopyCode = { ticket ->
                        clipboardManager.setText(AnnotatedString(ticket))
                        Toast.makeText(context, "Code copied to clipboard!", Toast.LENGTH_SHORT).show()
                    }
                )
            }
        }
    }
}

@Composable
fun GreenRoomPlaceholder(title: String, subtitle: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(100.dp)
                .clip(CircleShape)
                .background(Color(0xFF3C4043)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Videocam,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(40.dp)
            )
        }
        Spacer(modifier = Modifier.height(16.dp))
        Text(text = title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = subtitle,
            color = Color.Gray,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 32.dp)
        )
    }
}

@Composable
fun ParticipantVideoStage(uiState: AppUiState, isCameraOff: Boolean, isMuted: Boolean) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(280.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Color.Black.copy(alpha = 0.35f))
            .border(
                2.dp,
                if (uiState.localStreamId != null) Color.Green.copy(alpha = 0.3f) else Color.White.copy(alpha = 0.06f),
                RoundedCornerShape(16.dp)
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (uiState.localStreamId != null && !isCameraOff) {
                Icon(
                    imageVector = Icons.Default.Videocam,
                    contentDescription = null,
                    tint = Color.Green,
                    modifier = Modifier.size(48.dp)
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(text = "Android Live Streaming", color = Color.Green, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    repeat(8) {
                        Box(
                            modifier = Modifier
                                .width(3.dp)
                                .height(if (isMuted) 4.dp else Random.nextInt(8, 30).dp)
                                .background(if (isMuted) Color.Gray else Color.Green)
                        )
                    }
                }
            } else {
                Icon(
                    imageVector = Icons.Default.VideocamOff,
                    contentDescription = null,
                    tint = Color.Gray,
                    modifier = Modifier.size(48.dp)
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(text = "Camera Inactive", color = Color.Gray)
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(12.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(Color.Black.copy(alpha = 0.5f))
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = "${uiState.displayName} (You)",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 12.sp
            )
        }
    }
}

@Composable
fun DirectorClientsGrid(uiState: AppUiState, viewModel: AppViewModel) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        uiState.connectedClients.forEach { clientId ->
            val info = uiState.clientsMap[clientId]
            val name = info?.name ?: "Guest Feed"
            val device = info?.device ?: "Remote Device"

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(150.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color.Black.copy(alpha = 0.35f))
                    .border(
                        1.5.dp,
                        if (uiState.isRecording) Color.Red.copy(alpha = 0.4f) else Color.White.copy(alpha = 0.06f),
                        RoundedCornerShape(12.dp)
                    )
            ) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        repeat(6) {
                            Box(
                                modifier = Modifier
                                    .width(3.dp)
                                    .height(Random.nextInt(6, 26).dp)
                                    .background(if (uiState.isRecording) Color.Red else Color.Green)
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(text = device, color = Color.Gray, fontSize = 12.sp)
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color.Black.copy(alpha = 0.5f))
                            .padding(horizontal = 8.dp, vertical = 4.dp)
                    ) {
                        Text(text = name, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 11.sp)
                    }

                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.5f))
                            .clickable { viewModel.requestKeyframe(clientId) },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(14.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun CircularControlButton(
    icon: ImageVector,
    isActive: Boolean,
    activeColor: Color,
    inactiveColor: Color,
    onClick: () -> Void
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (isActive) activeColor else inactiveColor)
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Icon(imageVector = icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheetContent(
    uiState: AppUiState,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onCopyCode: (String) -> Unit
) {
    var ticketInput by remember { mutableStateOf("") }
    
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Meeting Setup", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Host Mode", color = Color.Gray, fontSize = 12.sp)
                Spacer(modifier = Modifier.width(6.dp))
                Switch(
                    checked = uiState.isDirector,
                    onCheckedChange = { viewModel.setMode(it) },
                    enabled = !uiState.isRunning && !uiState.isConnected
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        Divider(color = Color.White.copy(alpha = 0.08f))
        Spacer(modifier = Modifier.height(16.dp))

        // Profile details
        OutlinedTextField(
            value = uiState.displayName,
            onValueChange = { viewModel.updateDisplayName(it) },
            label = { Text("Display Name") },
            enabled = !uiState.isConnected,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(10.dp))

        OutlinedTextField(
            value = uiState.deviceType,
            onValueChange = { viewModel.updateDeviceType(it) },
            label = { Text("Device Type") },
            enabled = !uiState.isConnected,
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(20.dp))

        if (uiState.isDirector) {
            if (!uiState.isRunning) {
                Button(
                    onClick = {
                        viewModel.startDirector()
                        onDismiss()
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Start Hosting Room")
                }
            } else {
                Text("Room Active", fontWeight = FontWeight.Bold, color = Color.Green)
                Spacer(modifier = Modifier.height(6.dp))
                Button(
                    onClick = { onCopyCode(uiState.ticketText) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.DarkGray)
                ) {
                    Icon(imageVector = Icons.Default.ContentCopy, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Copy Joining Code")
                }
            }
        } else {
            if (!uiState.isConnected) {
                OutlinedTextField(
                    value = ticketInput,
                    onValueChange = { ticketInput = it },
                    label = { Text("Paste Joining Ticket JSON") },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(12.dp))
                Button(
                    onClick = {
                        viewModel.connectToDirector(ticketInput)
                        onDismiss()
                    },
                    enabled = ticketInput.isNotEmpty(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Connect to Meeting")
                }
            } else {
                Text("Connected successfully", color = Color.Green, fontWeight = FontWeight.Bold)
            }
        }

        Spacer(modifier = Modifier.height(20.dp))
        Divider(color = Color.White.copy(alpha = 0.08f))
        Spacer(modifier = Modifier.height(16.dp))

        // Logger View
        Text("System Logger", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(6.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Black)
                .padding(10.dp)
        ) {
            Text(
                text = uiState.statusMessage,
                color = Color.Green,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
