# mkv_cleanup_servarr
Automatically clean up video files from Sonarr and Radarr

Automatically cleans up video files
- Repackages into .mkv
- Removes unwanted subtitle languages
- Removes unwanted audio languages
- Sets permissions and ownership

## Dependencies
- mkvtoolnix
- jq
- ffprobe

## Example Usage
```
./mkv_cleanup_servarr.sh "/storage/tv/my show/"
./mkv_cleanup_servarr.sh "/storage/tv/my show/my show - season 01/my show - s01e01 - pilot.mp4"
```

## Adding to Sonarr or Radarr
![Screenshot of sonarr.](https://github.com/LRomandine/mkv_cleanup_servarr/blob/main/Readme_pic_2.jpg)
 
## Contributing
Posting this on Github to share with the community. I do not intend to support this but will welcome PRs.
