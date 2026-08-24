package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
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

	fmt.Printf("Loader: offset=%#x size=%d (%.1f KB)\n", loaderOffset, loaderLength, float64(loaderLength)/1024)
	fmt.Printf("Image:  offset=%#x size=%d (%.1f MB)\n", imageOffset, imageLength, float64(imageLength)/1024/1024)

	if _, err := imageFile.Seek(int64(imageOffset), io.SeekStart); err != nil {
		os.Exit(1)
	}

	rkafHeader := make([]byte, 0x800)
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
		partitionCount = 16
	}

	os.MkdirAll(outputDirectory, 0755)

	extractRange := func(offset, size int64, destinationPath string) error {
		if _, err := imageFile.Seek(offset, io.SeekStart); err != nil {
			return err
		}

		outFile, err := os.Create(destinationPath)
		if err != nil {
			return err
		}
		defer outFile.Close()

		_, err = io.CopyN(outFile, imageFile, size)
		return err
	}

	loaderOutputPath := filepath.Join(outputDirectory, "MiniLoaderAll.bin")
	if err := extractRange(int64(loaderOffset), int64(loaderLength), loaderOutputPath); err == nil {
		fmt.Printf("Extracted loader -> %s (%d bytes)\n", loaderOutputPath, loaderLength)
	}

	type flashTarget struct {
		name         string
		fileName     string
		flashAddress uint32
	}
	var pendingFlashTargets []flashTarget

	for index := 0; index < int(partitionCount); index++ {
		entryOffset := 0x8C + index*0x70
		partitionName := parseCString(rkafHeader[entryOffset : entryOffset+32])
		fileName := parseCString(rkafHeader[entryOffset+32 : entryOffset+32+60])
		relativePosition := readUint32LE(rkafHeader, entryOffset+0x60)
		flashAddress := readUint32LE(rkafHeader, entryOffset+0x64)
		entrySize := readUint32LE(rkafHeader, entryOffset+0x6C)

		if partitionName == "" || fileName == "" {
			continue
		}

		absoluteOffset := int64(imageOffset) + int64(relativePosition)
		partitionOutputPath := filepath.Join(outputDirectory, filepath.Base(fileName))

		if err := extractRange(absoluteOffset, int64(entrySize), partitionOutputPath); err != nil {
			fmt.Fprintf(os.Stderr, "  Error %s: %v\n", partitionName, err)
			continue
		}

		fmt.Printf("  [%2d] %-20s -> %-28s (%8.1f MB) flash@%#x\n",
			index, partitionName, partitionOutputPath, float64(entrySize)/1024/1024, flashAddress)

		if partitionName != "package-file" && partitionName != "bootloader" {
			pendingFlashTargets = append(pendingFlashTargets, flashTarget{
				name:         partitionName,
				fileName:     fileName,
				flashAddress: flashAddress,
			})
		}
	}

	fmt.Printf("\n -Flash commands- \n")
	for _, target := range pendingFlashTargets {
		fmt.Printf("rkdeveloptool wl %#06x %s\n",
			target.flashAddress, filepath.Join(outputDirectory, filepath.Base(target.fileName)))
	}
	fmt.Printf("rkdeveloptool rd\n")
}
