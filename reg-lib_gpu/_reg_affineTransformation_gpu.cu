/*
 *  _reg_affineTransformation_gpu.cu
 *
 *
 *  Created by Marc Modat on 25/03/2009.
 *  Copyright (c) 2009, University College London. All rights reserved.
 *  Centre for Medical Image Computing (CMIC)
 *  See the LICENSE.txt file in the nifty_reg root folder
 *
 */
#ifdef _USE_CUDA

#ifndef _REG_AFFINETRANSFORMATION_GPU_CU
#define _REG_AFFINETRANSFORMATION_GPU_CU

#include "_reg_affineTransformation_gpu.h"
#include "_reg_affineTransformation_gpu_kernels.cu"

/* *************************************************************** */
/* *************************************************************** */
void reg_affine_positionField_gpu(	mat44 *affineMatrix,
					nifti_image *targetImage,
					float4 **array_d)
{
	int3 imageSize = make_int3(targetImage->nx,targetImage->ny,targetImage->nz);
	CUDA_SAFE_CALL(cudaMemcpyToSymbol(c_ImageSize,&imageSize,sizeof(int3)));
	CUDA_SAFE_CALL(cudaMemcpyToSymbol(c_VoxelNumber,&(targetImage->nvox),sizeof(int)));

	// If the target sform is defined, it is used. The qform is used otherwise
	mat44 *targetMatrix;
	if(targetImage->sform_code>0)
		targetMatrix=&(targetImage->sto_xyz);
	else targetMatrix=&(targetImage->qto_xyz);

	// We here performed Affine * TargetMat * voxelIndex
	// Affine * TargetMat is constant
	mat44 transformationMatrix = reg_mat44_mul(affineMatrix, targetMatrix);

	// The transformation matrix is binded to a texture
	float4 *transformationMatrix_h;
    CUDA_SAFE_CALL(cudaMallocHost((void **)&transformationMatrix_h, 3*sizeof(float4)));
	float4 *transformationMatrix_d;
	CUDA_SAFE_CALL(cudaMalloc((void **)&transformationMatrix_d, 3*sizeof(float4)));
	for(int i=0; i<3; i++){
		transformationMatrix_h[i].x=transformationMatrix.m[i][0];
		transformationMatrix_h[i].y=transformationMatrix.m[i][1];
		transformationMatrix_h[i].z=transformationMatrix.m[i][2];
		transformationMatrix_h[i].w=transformationMatrix.m[i][3];
	}
	CUDA_SAFE_CALL(cudaMemcpy(transformationMatrix_d, transformationMatrix_h, 3*sizeof(float4), cudaMemcpyHostToDevice));
	cudaBindTexture(0,txAffineTransformation,transformationMatrix_d,3*sizeof(float4));
	
	const unsigned int Grid_reg_affine_deformationField = (unsigned int)ceil((float)targetImage->nvox/(float)Block_reg_affine_deformationField);
	dim3 B1(Block_reg_affine_deformationField,1,1);
	dim3 G1(Grid_reg_affine_deformationField,1,1);

	reg_affine_positionField_kernel <<< G1, B1 >>> (*array_d);
	CUDA_SAFE_CALL(cudaThreadSynchronize());
#if _VERBOSE
	printf("[VERBOSE] reg_affine_deformationField_kernel kernel: %s - Grid size [%i %i %i] - Block size [%i %i %i]\n",
	       cudaGetErrorString(cudaGetLastError()),G1.x,G1.y,G1.z,B1.x,B1.y,B1.z);
#endif
	
        // Unbind
	CUDA_SAFE_CALL(cudaUnbindTexture(txAffineTransformation));

	CUDA_SAFE_CALL(cudaFree(transformationMatrix_d));
	CUDA_SAFE_CALL(cudaFreeHost((void *)transformationMatrix_h));
}
/* *************************************************************** */
/* *************************************************************** */

#endif
#endif
