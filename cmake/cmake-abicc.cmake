SET(CMAKE_ABICC_DIR "${CMAKE_CURRENT_LIST_DIR}")

IF(NOT ABIComplianceChecker_FOUND)
	LIST(APPEND CMAKE_MODULE_PATH "${CMAKE_ABICC_DIR}")
	FIND_PACKAGE(ABIComplianceChecker REQUIRED)
ENDIF()

INCLUDE(CMakeParseArguments)

FUNCTION(ABICC_LIBRARIES)
	SET_PROPERTY(GLOBAL APPEND PROPERTY ABICC_LIBRARIES ${ARGV})
ENDFUNCTION()

FUNCTION(ABICC_HEADERS)
	FOREACH(header ${ARGV})
		GET_FILENAME_COMPONENT(abspath ${header} ABSOLUTE)
		SET_PROPERTY(GLOBAL APPEND PROPERTY
			     ABICC_HEADERS "${abspath}")
	ENDFOREACH()
ENDFUNCTION()

FUNCTION(ABICC_DUMP_FILE)
	CMAKE_PARSE_ARGUMENTS(ABICC "" "DUMP" "" ${ARGN})
	IF(NOT ABICC_DUMP)
		MESSAGE(FATAL_ERROR "Please specify DUMP filename!")
	ENDIF()
	IF(ABICC_UNPARSED_ARGUMENTS)
		MESSAGE(FATAL_ERROR "Unknown arguments specified: "
			"${ABICC_UNPARSED_ARGUMENTS}!")
	ENDIF()

	GET_PROPERTY(ABICC_LIBRARIES GLOBAL PROPERTY ABICC_LIBRARIES)
	IF(NOT ABICC_LIBRARIES)
		MESSAGE(FATAL_ERROR "Please specify atleast one library "
			"for ABI checking by ABICC_LIBRARIES()")
	ENDIF()

	GET_PROPERTY(ABICC_HEADERS GLOBAL PROPERTY ABICC_HEADERS)
	IF(NOT ABICC_HEADERS)
		MESSAGE(FATAL_ERROR "Please specify atlest one include "
			"directory or header file by ABICC_HEADERS()")
	ENDIF()

	# extract LIBS, INCLUDE_PATHS, GCC_OPTIONS, DEFINES, SEARCH_LIBS
	UNSET(DEFINES)
	UNSET(INCLUDE_PATHS)
	UNSET(LIBS)
	UNSET(SEARCH_LIBS)
	UNSET(search_libs)
	STRING(REPLACE " " ";" GCC_OPTIONS
	       "${CMAKE_C_FLAGS} ${CMAKE_CXX_FLAGS}")
	FOREACH(lib ${ABICC_LIBRARIES})
		LIST(APPEND LIBS "$<TARGET_LINKER_FILE:${lib}>")
		LIST(APPEND INCLUDE_PATHS
		     "$<TARGET_PROPERTY:${lib},INCLUDE_DIRECTORIES>")
		LIST(APPEND GCC_OPTIONS
		     "$<TARGET_PROPERTY:${lib},COMPILE_OPTIONS>")
		LIST(APPEND DEFINES
		     "$<TARGET_PROPERTY:${lib},COMPILE_DEFINITIONS>")

		# get library dependencies
		GET_TARGET_PROPERTY(prop ${lib} LINK_LIBRARIES)
		IF(prop)
			LIST(APPEND search_libs ${prop})
		ENDIF()
	ENDFOREACH()

	# escape HEADERS
	LIST(REMOVE_DUPLICATES ABICC_HEADERS)
	STRING(REPLACE ";" "$<SEMICOLON>" HEADERS "${ABICC_HEADERS}")

	# escape LIBS
	LIST(REMOVE_DUPLICATES LIBS)
	STRING(REPLACE ";" "$<SEMICOLON>" LIBS "${LIBS}")

	# escape INCLUDE_PATHS
	LIST(REMOVE_DUPLICATES INCLUDE_PATHS)
	LIST(REMOVE_ITEM INCLUDE_PATHS "")
	STRING(REPLACE ";" "$<SEMICOLON>" INCLUDE_PATHS "${INCLUDE_PATHS}")

	# escape GCC_OPTIONS
	LIST(REMOVE_DUPLICATES GCC_OPTIONS)
	LIST(REMOVE_ITEM GCC_OPTIONS "")
	STRING(REPLACE ";" "$<SEMICOLON>" GCC_OPTIONS "${GCC_OPTIONS}")

	# escape DEFINES
	LIST(REMOVE_DUPLICATES DEFINES)
	STRING(REPLACE ";" "$<SEMICOLON>" DEFINES "${DEFINES}")

	# TOOLS
	SET(TOOLS
		${ABICC_LDCONFIG_DIR}
		${ABICC_COMPILER_PATH}
		${CTAGS_PATH})
	LIST(REMOVE_DUPLICATES TOOLS)
	STRING(REPLACE ";" "$<SEMICOLON>" TOOLS "${TOOLS}")

	# escape SEARCH_LIBS
	FOREACH(lib ${search_libs})
		IF(TARGET ${lib})
			LIST(APPEND SEARCH_LIBS "$<TARGET_FILE:${lib}>")
		ELSEIF(EXISTS ${lib})
			LIST(APPEND SEARCH_LIBS "${lib}")
		ELSE()
			MESSAGE(WARNING "Unknown target ${lib}")
		ENDIF()
	ENDFOREACH()
	IF(SEARCH_LIBS)
		LIST(REMOVE_DUPLICATES SEARCH_LIBS)
		STRING(REPLACE ";" "$<SEMICOLON>" SEARCH_LIBS "${SEARCH_LIBS}")
	ENDIF()

	SET(PROJECT_ABICC_XML
		"${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.abicc.xml")
	ADD_CUSTOM_COMMAND(OUTPUT "${PROJECT_ABICC_XML}"
	COMMAND
		${CMAKE_COMMAND}
	ARGS
		-DVERSION=${PROJECT_VERSION}
		-DHEADERS="${HEADERS}"
		-DLIBS="${LIBS}"
		-DINCLUDE_PATHS="${INCLUDE_PATHS}"
		-DGCC_OPTIONS="${GCC_OPTIONS}"
		-DDEFINES="${DEFINES}"
		-DCROSS_PREFIX="${ABICC_CROSS_PREFIX}"
		-DTOOLS="${TOOLS}"
		-DSEARCH_LIBS="${SEARCH_LIBS}"
		-DCMAKE_ABICC_DIR="${CMAKE_ABICC_DIR}"
		-DPROJECT_ABICC_XML="${PROJECT_ABICC_XML}"
		-P "${CMAKE_ABICC_DIR}/descriptor.cmake"
	COMMENT
		"Generate ABICC xml for ${PROJECT_NAME}")

	ADD_CUSTOM_COMMAND(OUTPUT "${ABICC_DUMP}"
	COMMAND
		${ABICC_EXECUTABLE}
	ARGS
		--v1=${PROJECT_VERSION}
		-lib ${PROJECT_NAME}
		-dump ${PROJECT_ABICC_XML}
		-dump-path ${ABICC_DUMP}
		-dump-format xml
	DEPENDS
		"${PROJECT_ABICC_XML}"
	COMMENT
		"Generate ABICC dump for ${PROJECT_NAME}")

	ADD_CUSTOM_TARGET(${PROJECT_NAME}_abicc_dump
	DEPENDS
		"${ABICC_DUMP}")
ENDFUNCTION()

FUNCTION(ABICC_COMPARE)
	CMAKE_PARSE_ARGUMENTS(ABICC "" "OLD;NEW" "" ${ARGN})
	IF(NOT ABICC_OLD)
		MESSAGE(FATAL_ERROR "OLD not specified")
	ENDIF()
	IF(NOT ABICC_NEW)
		MESSAGE(FATAL_ERROR "NEW not specified")
	ENDIF()
	IF(ABICC_UNPARSED_ARGUMENTS)
		MESSAGE(FATAL_ERROR "Unknown arguments specified: "
			"${ABICC_UNPARSED_ARGUMENTS}!")
	ENDIF()

	GET_FILENAME_COMPONENT(old_file "${ABICC_OLD}" NAME)
	GET_FILENAME_COMPONENT(new_file "${ABICC_NEW}" NAME)
	SET(ABICC_REPORT "${CMAKE_CURRENT_BINARY_DIR}/compatibility.html")
	ADD_CUSTOM_COMMAND(OUTPUT "${ABICC_REPORT}.chk"
	COMMAND
		${ABICC_EXECUTABLE}
	ARGS
		-l "${PROJECT_NAME}"
		-old "${ABICC_OLD}"
		-new "${ABICC_NEW}"
		-report-path "${ABICC_REPORT}"
		--report-format=html
		-strict
	COMMAND
		"${CMAKE_COMMAND}"
	ARGS
		-E touch "${ABICC_REPORT}.chk"
	DEPENDS
		"${ABICC_OLD}"
		"${ABICC_NEW}"
	COMMENT
		"Compare ABICC dumps ${old_file} vs ${new_file}")

	ADD_CUSTOM_TARGET(${PROJECT_NAME}_abicc ALL
	DEPENDS
		"${ABICC_REPORT}.chk"
	COMMENT
		"Generate '${ABICC_REPORT}'")
ENDFUNCTION()
