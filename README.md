# Windows Task Runner

Easily run **interactive (GUI)** tasks via the Windows Task Scheduler—even when no one is logged on. This uses **only** native Windows RDP—no extra tools or external credential storage.

## Motivation

By default, Windows Task Scheduler does **not** allow GUI tasks when nobody is logged in. This project creates a **local** RDP session on `127.0.0.2` or any other loopback address, allowing graphical applications to run unattended. It also works for non-interactive jobs, providing a **single solution** for all scheduled tasks.

## Features

- **Run GUI Tasks**  
  Start GUI-based apps (e.g., desktop automation or UI tests) without a manually logged-on user.  
  - Technically, an "active" RDP session is created, but you don't need to **manually** log on—this is handled automatically by the script.

- **No External Software**  
  Only requires built-in Windows RDP—no additional tools like FreeRDP, port forwarding, or third-party vaults.

- **Session Persistence**  
  - You can connect locally (e.g., `127.0.0.2`) to **observe** the GUI.  
  - Disconnect without terminating the session or the task.

- **Automated Session Switching**  
  If a user session is currently active, it is disconnected to free up the GUI context. The new session then runs your interactive task.

- **No Plain-Text Credentials**  
  Credentials live in the standard Windows Credential Manager.

## Requirements

**Tested Windows Versions**: This solution has been tested and confirmed working on Windows Server 2008, 2016, 2019, and 2022. It also works on Windows 10/11 Pro/Enterprise editions.

**Important Note**: The ability to monitor your interactive tasks through the loopback RDP connection depends on having multiple RDP sessions enabled. With only a single session allowed, you won't be able to connect for monitoring while your automated task is running.

1. **Enable Concurrent RDP Sessions**  
   - **Best practice**: allow multiple (or at least two) RDP sessions in Local/Group Policy.  
   - If only a single session is allowed, once someone manually logs in via RDP, it might disconnect the session hosting your interactive task.

   **Step-by-step instructions**:
   
   **Option A: Local Group Policy Editor (Windows Pro/Enterprise/Server)**
   - Press `Win + R`, type `gpedit.msc`, press Enter
   - Navigate to: `Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Connection Host → Connections`
   - Double-click "Limit number of connections"
   - Set to "Enabled" and set the value to `2` or higher
   
   **Option B: Registry Editor (All Windows versions)**
   - Press `Win + R`, type `regedit`, press Enter
   - Navigate to: `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services`
   - Create DWORD value: `MaxConnections` with value `2` or higher
   
   **Note**: Windows 10/11 Pro/Enterprise and Windows Server support multiple RDP sessions. Windows 10/11 Home has limited RDP functionality.

2. **Windows Credential for Loopback**  
   - Create a generic credential mapping a loopback address (e.g., `127.0.0.2`) to the user running the tasks.

3. **RDP Config File (Mandatory for Interactive Tasks)**  
   - Provide a `.rdp` file (pointing to your chosen loopback IP) to the script via `-RDPConfig`.  
   - You can also use this file to manually RDP in to see what's running.

4. **Grant "Log on as a batch job" Right**  
   - In **Security Settings → Local Policies → User Rights Assignment**, ensure the user account that runs these tasks is explicitly added to **"Log on as a batch job."**  
   - Without this, the system may block non-interactive or scheduled runs, resulting in access errors.

   **Step-by-step instructions**:
   
   **Option A: Local Security Policy (Windows Pro/Enterprise/Server)**
   - Press `Win + R`, type `secpol.msc`, press Enter
   - Navigate to: `Security Settings → Local Policies → User Rights Assignment`
   - Double-click "Log on as a batch job"
   - Click "Add User or Group" and add your service account
   
   **Option B: Group Policy Editor (Windows Pro/Enterprise/Server)**
   - Press `Win + R`, type `gpedit.msc`, press Enter
   - Navigate to: `Computer Configuration → Windows Settings → Security Settings → Local Policies → User Rights Assignment`
   - Double-click "Log on as a batch job"
   - Click "Add User or Group" and add your service account
   
   **Option C: Registry Editor (All Windows versions)**
   - Press `Win + R`, type `regedit`, press Enter
   - Navigate to: `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`
   - Look for existing values or create appropriate registry entries for batch logon rights

## How It Works

1. **Disconnect Existing Session**  
   The script logs off any currently active session of the same user.

2. **Establish Loopback RDP**  
   It then launches `mstsc.exe` pointing to the loopback address (e.g., `127.0.0.2`), using stored Windows credentials. The GUI process starts in this new session.

3. **Optional Monitoring**  
   Connect to the same `.rdp` file to watch the task. Disconnect at any time—your task keeps running.

4. **Non-Interactive**  
   For headless jobs, you can omit the `-RDPConfig` parameter and run them in the background.

## Usage Example (Task Scheduler)

Below you can find the steps to run any given task using TaskRunner:

### 1. Create Your Target Task (No Schedule Yet)
- **Example Name**: `TypeIntoNotepad`  
- **Action**: Points to your actual script/application (e.g., "type text into Notepad").  
- **Scheduling**: Leave it as "Run on demand" or no schedule.  
- **Note**: Do **not** set any schedule on this task; it's the underlying action to be triggered by TaskRunner.

### 2. Create a Wrapper Task Using TaskRunner to Call the Target Task
- **Example Name**: `TypeIntoNotepad-Runner`  
- **Action**: "Start a program"  
  - **Program/Script**:  
    ```
    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
    ```
  - **Arguments**:  
    ```
    .\RunTask.ps1 -TaskName "TypeIntoNotepad" -RDPConfig "C:\Users\YourUserName\Desktop\Default.rdp"
    ```
  - **Start In**:  
    ```
    C:\Users\YourUserName\Documents\dev\WindowsInteractiveTask\scripts
    ```
- **Run whether user is logged on or not**: checked  
- **Scheduling**: Configure this TaskRunner for daily, weekly, or any desired schedule.  
- **Behavior**: When triggered, TaskRunner executes:
  ```
  schtasks /run /tn "TypeIntoNotepad"
  ```
  behind the scenes.

### 3. (Optional) Convert the Script to an `.exe`
If you'd prefer a single executable over a `.ps1`:

1. Install ps2exe:
   ```powershell
   Install-Module -Name ps2exe -Force
   ```
2. Convert the script:
   ```powershell
   ps2exe .\scripts\RunTask.ps1 .\scripts\RunTask.exe
   ```
3. Update your TaskRunner to reference the generated `.exe` instead of the `.ps1`.

### How It Works
- **TaskRunner** is the task that actually has a schedule.  
- On trigger, **TaskRunner** runs **`RunTask.ps1 (or .exe)`**, which then calls your **target task** (e.g., `TypeIntoNotepad`).  
- If `-RDPConfig` is supplied, TaskRunner sets up an **interactive RDP session**, allowing GUI-based tasks to run even when no one is logged on.

## Technical Implementation

The `RunTask.ps1` script provides sophisticated session management:

- **Process Identification**: Uses `Get-NetTCPConnection` to find RDP client processes by remote address
- **Session Management**: Leverages `query user` and `logoff` commands for session control
- **RDP Automation**: Launches `mstsc.exe` with predefined configuration files
- **Task Orchestration**: Integrates with `schtasks` for Windows Task Scheduler operations
- **Logging**: Automatically generates execution logs at `C:\ProgramData\TaskRunner\TaskRunner.log`

## Installation

1. **Download the Script**
   ```powershell
   # Clone or download RunTask.ps1 to your target system
   # Recommended location: C:\ProgramData\TaskRunner\
   ```

2. **Create Required Directories**
   ```powershell
   New-Item -ItemType Directory -Path "C:\ProgramData\TaskRunner" -Force
   ```

3. **Set Execution Policy** (if required)
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
   ```

## Monitoring and Troubleshooting

### Session Monitoring
- Connect to the same RDP configuration file to observe running tasks
- Use `query user` command to monitor active sessions
- Disconnect monitoring sessions without affecting task execution

### Common Issues

1. **"Access Denied" Errors**
   - Verify the service account has "Log on as a batch job" rights
   - Check Windows Task Scheduler permissions

2. **RDP Connection Failures**
   - Validate the `.rdp` file configuration
   - Ensure credentials are properly stored in Windows Credential Manager
   - Verify loopback address accessibility

3. **Task Execution Failures**
   - Confirm the target task name exists
   - Check task permissions and dependencies
   - Review Windows Event Logs for detailed error information

## Security Considerations

- **Local Execution Only**: This solution operates entirely within the local system
- **No External Dependencies**: Uses only built-in Windows components
- **Credential Management**: Leverages Windows Credential Manager for secure storage
- **Session Isolation**: Creates isolated RDP sessions for task execution

## Limitations

- Requires Windows RDP services to be enabled
- Limited to local system execution (no remote deployment)
- Dependent on Windows Task Scheduler functionality
- May conflict with existing RDP session policies

## Contributing

All suggestions are welcome! Open an issue or pull request to enhance or fix interactive session management.

## License

Provided as-is, with no specific license. Use it freely within your environment—no warranties or guarantees.

## Disclaimer

Review your organization's security requirements before using. This script changes how RDP sessions are handled—make sure it aligns with your policies.