package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"unicode"
)

func readUint32LE(data []byte, offset int) uint32 {
	return binary.LittleEndian.Uint32(data[offset : offset+4])
}

func parseCString(data []byte) string {
	for index, char := range data {
		if char == 0 {
			return strings.TrimSpace(string(data[:index]))
		}
	}

	return strings.TrimSpace(string(data))
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <update.img> [output_dir]\n", os.Args[0])
		os.Exit(1)
	}

	inputImagePath := os.Args[1]
	outputDirectory := "firmware"
	if len(os.Args) >= 3 {
		outputDirectory = os.Args[2]
	}

	imageFile, err := os.Open(inputImagePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	defer imageFile.Close()

	rkfwHeader := make([]byte, 0x66)
	if _, err := io.ReadFull(imageFile, rkfwHeader); err != nil {
		fmt.Fprintf(os.Stderr, "read err\n")
		os.Exit(1)
	}
	if string(rkfwHeader[0:4]) != "RKFW" {
		fmt.Fprintf(os.Stderr, "Not RKFW: %q\n", string(rkfwHeader[0:4]))
		os.Exit(1)
	}

	loaderOffset := readUint32LE(rkfwHeader, 0x19)
	loaderLength := readUint32LE(rkfwHeader, 0x1D)
	imageOffset := readUint32LE(rkfwHeader, 0x21)
	imageLength := readUint32LE(rkfwHeader, 0x25)
	imageInfo, err := imageFile.Stat()
	if err != nil {
		fmt.Fprintf(os.Stderr, "stat input image: %v\n", err)
		os.Exit(1)
	}
	imageSize := imageInfo.Size()
	if int64(imageOffset) > imageSize || int64(imageLength) > imageSize-int64(imageOffset) {
		fmt.Fprintln(os.Stderr, "declared image payload is outside the input file")
		os.Exit(1)
	}

	fmt.Printf("Loader: offset=%#x size=%d (%.1f KB)\n", loaderOffset, loaderLength, float64(loaderLength)/1024)
	fmt.Printf("Image:  offset=%#x size=%d (%.1f MB)\n", imageOffset, imageLength, float64(imageLength)/1024/1024)

	rkafHeader := make([]byte, 0x800)
	if int64(imageLength) < int64(len(rkafHeader)) {
		fmt.Fprintln(os.Stderr, "declared RKAF payload is too small for its header")
		os.Exit(1)
	}

	if _, err := imageFile.Seek(int64(imageOffset), io.SeekStart); err != nil {
		fmt.Fprintf(os.Stderr, "seek to RKAF header: %v\n", err)
		os.Exit(1)
	}

	if _, err := io.ReadFull(imageFile, rkafHeader); err != nil {
		fmt.Fprintf(os.Stderr, "read RKAF header: %v\n", err)
		os.Exit(1)
	}
	if string(rkafHeader[0:4]) != "RKAF" {
		fmt.Fprintf(os.Stderr, "RKAF mismatch at %#x got %q\n", imageOffset, string(rkafHeader[0:4]))
		os.Exit(1)
	}

	deviceModel := parseCString(rkafHeader[0x08 : 0x08+0x22])
	partitionCount := readUint32LE(rkafHeader, 0x88)
	fmt.Printf("Model: %s | Partitions: %d\n\n", deviceModel, partitionCount)

	if partitionCount > 16 {
		fmt.Fprintf(os.Stderr, "invalid RKAF partition count: %d (maximum 16)\n", partitionCount)
		os.Exit(1)
	}

	extractRange := func(offset, size int64, destinationPath string) error {
		if offset < 0 || size < 0 || offset > imageSize || size > imageSize-offset {
			return fmt.Errorf("range [%#x, %#x) is outside the %d-byte image", offset, offset+size, imageSize)
		}
		if size == 0 {
			return fmt.Errorf("refusing to extract an empty range")
		}
		if _, err := imageFile.Seek(offset, io.SeekStart); err != nil {
			return err
		}

		outFile, err := os.Create(destinationPath)
		if err != nil {
			return err
		}

		_, err = io.CopyN(outFile, imageFile, size)
		if err != nil {
			outFile.Close()
			return err
		}
		return outFile.Close()
	}

	type partition struct {
		index        int
		name         string
		baseName     string
		relativePos  uint32
		flashAddress uint32
		size         uint32
	}
	type flashTarget struct {
		baseName     string
		flashAddress uint32
	}
	partitions := make([]partition, 0, partitionCount)
	var pendingFlashTargets []flashTarget
	seenOutputNames := map[string]struct{}{"MiniLoaderAll.bin": {}}

	for index := 0; index < int(partitionCount); index++ {
		entryOffset := 0x8C + index*0x70
		partitionName := parseCString(rkafHeader[entryOffset : entryOffset+32])
		fileName := parseCString(rkafHeader[entryOffset+32 : entryOffset+32+60])
		relativePosition := readUint32LE(rkafHeader, entryOffset+0x60)
		flashAddress := readUint32LE(rkafHeader, entryOffset+0x64)
		entrySize := readUint32LE(rkafHeader, entryOffset+0x6C)

		if partitionName == "" && fileName == "" {
			continue
		}
		if partitionName == "" || fileName == "" {
			fmt.Fprintf(os.Stderr, "invalid RKAF partition entry %d: missing partition or file name\n", index)
			os.Exit(1)
		}
		if strings.IndexFunc(partitionName, unicode.IsControl) >= 0 {
			fmt.Fprintf(os.Stderr, "invalid control character in partition name at entry %d\n", index)
			os.Exit(1)
		}
		baseName := filepath.Base(fileName)
		if baseName == "." || baseName == ".." || baseName == string(filepath.Separator) || strings.IndexFunc(baseName, unicode.IsControl) >= 0 {
			fmt.Fprintf(os.Stderr, "invalid output filename for partition %s: %q\n", partitionName, fileName)
			os.Exit(1)
		}
		if _, exists := seenOutputNames[baseName]; exists {
			fmt.Fprintf(os.Stderr, "duplicate RKAF output filename %q\n", baseName)
			os.Exit(1)
		}
		seenOutputNames[baseName] = struct{}{}
		if entrySize == 0 || uint64(relativePosition)+uint64(entrySize) > uint64(imageLength) {
			fmt.Fprintf(os.Stderr, "partition %s has an invalid range in the declared image payload\n", partitionName)
			os.Exit(1)
		}
		partitions = append(partitions, partition{
			index:        index,
			name:         partitionName,
			baseName:     baseName,
			relativePos:  relativePosition,
			flashAddress: flashAddress,
			size:         entrySize,
		})
		if partitionName != "package-file" && partitionName != "bootloader" {
			pendingFlashTargets = append(pendingFlashTargets, flashTarget{
				baseName:     baseName,
				flashAddress: flashAddress,
			})
		}
	}

	if err := os.MkdirAll(outputDirectory, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "create output directory: %v\n", err)
		os.Exit(1)
	}
	loaderOutputPath := filepath.Join(outputDirectory, "MiniLoaderAll.bin")
	if err := extractRange(int64(loaderOffset), int64(loaderLength), loaderOutputPath); err != nil {
		fmt.Fprintf(os.Stderr, "extract loader: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Extracted loader -> %s (%d bytes)\n", loaderOutputPath, loaderLength)

	for _, partition := range partitions {
		absoluteOffset := int64(imageOffset) + int64(partition.relativePos)
		partitionOutputPath := filepath.Join(outputDirectory, partition.baseName)
		if err := extractRange(absoluteOffset, int64(partition.size), partitionOutputPath); err != nil {
			fmt.Fprintf(os.Stderr, "extract partition %s: %v\n", partition.name, err)
			os.Exit(1)
		}
		fmt.Printf("  [%2d] %-20s -> %-28s (%8.1f MB) flash@%#x\n",
			partition.index, partition.name, partitionOutputPath, float64(partition.size)/1024/1024, partition.flashAddress)
	}

	fmt.Printf("\n -Flash commands- \n")
	for _, target := range pendingFlashTargets {
		fmt.Printf("rkdeveloptool wl %#06x %s\n",
			target.flashAddress, shellQuote(filepath.Join(outputDirectory, target.baseName)))
	}
	fmt.Printf("rkdeveloptool rd\n")
}
