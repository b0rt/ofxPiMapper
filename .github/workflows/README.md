# GitHub Actions Workflows for ofxPiMapper

This directory contains GitHub Actions workflows for automated building and testing.

## Available Workflows

### `build-image.yml` - Automated Image Building

Automatically builds bootable Raspberry Pi images with ofxPiMapper pre-installed.

#### Triggers

1. **Release Creation** - Automatically builds when a new release is created
2. **Manual Dispatch** - Manually trigger with custom configuration via GitHub UI
3. **Push to Main** (optional) - Can be enabled for automatic builds on commits

#### Manual Build Instructions

1. Go to the **Actions** tab in your GitHub repository
2. Select **"Build ofxPiMapper Raspberry Pi Image"** workflow
3. Click **"Run workflow"** button
4. Configure options:
   - **Username:** Raspberry Pi username (default: `mapper`)
   - **Password:** Raspberry Pi password (default: `projection`)
   - **Hostname:** System hostname (default: `ofxpimapper`)
   - **Auto-start:** Enable auto-start on boot (`true`/`false`)
   - **Base Image:** OS type (`lite` or `desktop`)
   - **openFrameworks Version:** OF version to install (default: `0.12.0`)
   - **Compress Image:** Create compressed .zip file (`true`/`false`)
5. Click **"Run workflow"**

#### Build Process

The workflow will:
1. ✅ Checkout repository
2. ✅ Free up disk space (removes unnecessary GitHub Actions tools)
3. ✅ Install build dependencies
4. ✅ Generate build configuration from inputs
5. ✅ Build image using pi-gen with Docker
6. ✅ Create checksums and build info
7. ✅ Upload artifacts to GitHub
8. ✅ Attach to release (if triggered by release)

#### Build Time

- **Typical Duration:** 2-4 hours
- **Maximum Timeout:** 6 hours
- **GitHub Actions Limit:** Free tier has usage limits

#### Artifacts

After successful build, the following artifacts are available:

1. **Image File:** `ofxpimapper-rpi4-YYYY-MM-DD.img` (~3.5-4.5 GB)
2. **Compressed Image:** `ofxpimapper-rpi4-YYYY-MM-DD.img.zip` (~2-3 GB)
3. **Checksum:** `ofxpimapper-rpi4-YYYY-MM-DD.img.sha256`
4. **Build Info:** `BUILD_INFO.txt` (configuration details)
5. **Build Log:** `build.log` (complete build output)

#### Downloading Artifacts

##### From Workflow Run
1. Go to **Actions** tab
2. Click on the completed workflow run
3. Scroll to **Artifacts** section at the bottom
4. Download `ofxpimapper-image`
5. Extract and flash to SD card

##### From Release
If triggered by a release, artifacts are automatically attached:
1. Go to **Releases** tab
2. Find your release
3. Download image files from **Assets** section

#### Flashing to SD Card

```bash
# Extract if compressed
unzip ofxpimapper-rpi4-*.img.zip

# Verify checksum (optional)
sha256sum -c ofxpimapper-rpi4-*.img.sha256

# Flash to SD card (Linux/macOS)
sudo dd if=ofxpimapper-rpi4-*.img of=/dev/sdX bs=4M status=progress conv=fsync

# Or use Raspberry Pi Imager (all platforms)
# https://www.raspberrypi.com/software/
```

## Configuration Examples

### Development Build

```yaml
Username: dev
Password: dev
Hostname: ofxpi-dev
Auto-start: false
Base Image: desktop
openFrameworks: 0.12.0
Compress: true
```

### Production Build

```yaml
Username: mapper
Password: [secure-password]
Hostname: production-mapper
Auto-start: true
Base Image: desktop
openFrameworks: 0.12.0
Compress: true
```

### Minimal Build

```yaml
Username: mapper
Password: projection
Hostname: ofxpimapper
Auto-start: false
Base Image: lite
openFrameworks: 0.12.0
Compress: true
```

## Automated Releases

To automatically build and attach images to releases:

1. Create a new release on GitHub:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. Create release through GitHub UI:
   - Go to **Releases** → **Draft a new release**
   - Choose tag: `v1.0.0`
   - Fill in release notes
   - Click **Publish release**

3. Workflow automatically builds and attaches image to the release

## GitHub Actions Limits

### Free Tier
- **Storage:** 500 MB artifact storage
- **Compute:** 2,000 minutes/month
- **Concurrent Jobs:** Up to 20

### Considerations
- Each build uses ~3-4 hours of compute time
- Artifacts are large (3-4 GB), may hit storage limits
- Use artifact retention (default: 30 days) to manage storage
- Consider using self-hosted runners for unlimited builds

## Self-Hosted Runners

For unlimited builds or faster compilation, set up a self-hosted runner:

### Setup

1. Go to **Settings** → **Actions** → **Runners**
2. Click **New self-hosted runner**
3. Follow setup instructions for your platform

### Requirements for Self-Hosted Runner
- Ubuntu 20.04+ or Debian 11+
- 30 GB free disk space
- 4 GB RAM minimum
- Docker installed (for pi-gen builds)

### Modify Workflow for Self-Hosted

```yaml
jobs:
  build-image:
    runs-on: self-hosted  # Instead of ubuntu-22.04
    # ... rest of workflow
```

## Troubleshooting

### Build Fails: "No space left on device"

**Solution:** Workflow includes disk cleanup, but if still failing:
- Use self-hosted runner with more space
- Reduce base image size (use `lite` instead of `desktop`)

### Build Timeout

**Solution:**
- Increase `timeout-minutes` in workflow (max 6 hours for free tier)
- Use faster self-hosted runner

### Artifact Upload Fails

**Solution:**
- Check artifact size (must be < 2 GB per file for upload)
- Ensure compression is enabled
- Split large files if necessary

### Docker Permission Errors

**Solution:** Workflow uses Docker mode which shouldn't need root, but if issues:
- Check Docker is installed on runner
- Verify runner user has Docker permissions

## Advanced Usage

### Custom Workflow Modifications

Edit `.github/workflows/build-image.yml` to customize:

#### Add Notification on Completion
```yaml
- name: Notify on completion
  if: success()
  uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: '✅ Image build complete! Download from artifacts.'
      })
```

#### Run Tests After Build
```yaml
- name: Test image in QEMU
  run: |
    cd build-system/testing
    timeout 10m ./test-qemu.sh ../pi-gen-method/deploy/*.img
```

#### Upload to Cloud Storage
```yaml
- name: Upload to S3
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1

- name: Copy to S3
  run: |
    aws s3 cp build-system/pi-gen-method/deploy/*.img \
      s3://my-bucket/ofxpimapper/
```

## Security Considerations

### Passwords in Workflows

**IMPORTANT:** Do not use default passwords in production builds!

For secure password handling:

1. Create repository secret:
   - Go to **Settings** → **Secrets and variables** → **Actions**
   - Click **New repository secret**
   - Name: `RPI_PASSWORD`
   - Value: Your secure password

2. Use in workflow:
   ```yaml
   rpi_password:
     description: 'Raspberry Pi password'
     required: false
     default: ${{ secrets.RPI_PASSWORD }}
   ```

### Build Logs

Build logs may contain sensitive information:
- Passwords are visible in configuration
- Network settings exposed
- Consider using private repositories for sensitive builds

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [ofxPiMapper Build System](../build-system/README.md)

## Support

- **Issues:** https://github.com/b0rt/ofxPiMapper/issues
- **Build System Docs:** `build-system/README.md`
- **Troubleshooting:** `build-system/docs/TROUBLESHOOTING.md`
